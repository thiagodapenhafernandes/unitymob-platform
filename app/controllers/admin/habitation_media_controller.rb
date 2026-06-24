class Admin::HabitationMediaController < Admin::BaseController
  before_action -> { check_permission!(:view, :imoveis) }
  before_action :set_habitation
  before_action :scope_habitation_by_permission
  before_action :load_property_setting

  def show
    @page_title = "Mídia do Imóvel: #{@habitation.codigo}"
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])
  end

  def modal
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])

    render partial: "admin/habitations/media/modal_content",
           layout: false,
           locals: {
             habitation: @habitation,
             return_to_path: @return_to_path
           }
  end

  def update
    @page_title = "Mídia do Imóvel: #{@habitation.codigo}"
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])

    before_snapshot = Habitations::AuditChangeRecorder.snapshot_for(@habitation)
    @habitation.skip_auto_audit = true

    permitted_attributes = habitation_media_params
    media_update = habitation_media_updater
    new_photo_uploads = media_update.extract_photo_uploads!(permitted_attributes)
    @habitation.assign_attributes(permitted_attributes)
    media_update.touch_manual_habitation_update!(force: new_photo_uploads.present? || media_update.media_removal_requested?)
    media_update.apply_picture_removals_to_memory

    if @habitation.save
      media_update.attach_new_photos(new_photo_uploads)
      media_update.record_habitation_updated(before_snapshot: before_snapshot)
      media_update.apply_saved_photo_removals

      respond_to do |format|
        format.html do
          redirect_to admin_habitation_media_path(@habitation, return_to: @return_to_path),
                      notice: "Mídia atualizada com sucesso."
        end
        format.json do
          @habitation.reload
          render json: media_response_payload(message: "Mídia atualizada com sucesso.")
        end
      end
    else
      respond_to do |format|
        format.html { render :show, status: :unprocessable_entity }
        format.json { render json: { ok: false, errors: @habitation.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def upload
    before_snapshot = Habitations::AuditChangeRecorder.snapshot_for(@habitation)
    @habitation.skip_auto_audit = true

    media_update = habitation_media_updater
    permitted_attributes = upload_params
    new_photo_uploads = media_update.extract_photo_uploads!(permitted_attributes)

    if new_photo_uploads.blank?
      respond_with_media_error("Selecione ao menos uma foto para enviar.")
      return
    end

    media_update.touch_manual_habitation_update!(force: true)

    if @habitation.save
      media_update.attach_new_photos(new_photo_uploads)
      media_update.record_habitation_updated(before_snapshot: before_snapshot)
      respond_with_media_success("Fotos enviadas com sucesso.")
    else
      respond_with_media_validation_error
    end
  end

  def reorder
    before_snapshot = Habitations::AuditChangeRecorder.snapshot_for(@habitation)
    @habitation.skip_auto_audit = true

    permitted_attributes = reorder_params
    @habitation.assign_attributes(permitted_attributes)
    habitation_media_updater.touch_manual_habitation_update!

    if @habitation.save
      habitation_media_updater.record_habitation_updated(before_snapshot: before_snapshot)
      respond_with_media_success("Ordem da mídia atualizada.")
    else
      respond_with_media_validation_error
    end
  end

  def visibility
    before_snapshot = Habitations::AuditChangeRecorder.snapshot_for(@habitation)
    @habitation.skip_auto_audit = true

    permitted_attributes = visibility_params
    @habitation.assign_attributes(permitted_attributes)
    habitation_media_updater.touch_manual_habitation_update!

    if @habitation.save
      habitation_media_updater.record_habitation_updated(before_snapshot: before_snapshot)
      respond_with_media_success("Visibilidade da mídia atualizada.")
    else
      respond_with_media_validation_error
    end
  end

  def destroy_photo
    before_snapshot = Habitations::AuditChangeRecorder.snapshot_for(@habitation)
    @habitation.skip_auto_audit = true
    media_update = habitation_media_updater

    photo_id = numeric_param(:photo_id)
    picture_index = numeric_param(:picture_index)

    if photo_id.blank? && picture_index.blank?
      respond_with_media_error("Informe a foto que deve ser removida.")
      return
    end

    media_update.apply_picture_removals_to_memory([picture_index]) if picture_index.present?
    media_update.touch_manual_habitation_update!(force: true)

    if @habitation.save
      media_update.record_habitation_updated(before_snapshot: before_snapshot)
      media_update.apply_saved_photo_removals([photo_id]) if photo_id.present?
      respond_with_media_success("Foto removida.")
    else
      respond_with_media_validation_error
    end
  end

  private

  def habitation_media_params
    permitted = params.require(:habitation).permit(
      :foto_classificacao,
      :use_development_photos_flag,
      :ordered_photo_ids,
      :ordered_picture_indices,
      :site_hidden_photo_ids,
      :site_hidden_picture_urls,
      :tour_virtual,
      :podcast_url,
      videos: [],
      photos: []
    )

    strip_blank_photo_uploads!(permitted)
  end

  def upload_params
    permitted = params.require(:habitation).permit(:apply_photo_watermark, photos: [])
    strip_blank_photo_uploads!(permitted)
  end

  def reorder_params
    params.require(:habitation).permit(:ordered_photo_ids, :ordered_picture_indices)
  end

  def visibility_params
    params.require(:habitation).permit(:site_hidden_photo_ids, :site_hidden_picture_urls)
  end

  def strip_blank_photo_uploads!(permitted)
    Habitations::MediaUpdater.strip_blank_photo_uploads!(permitted)
  end

  def habitation_media_updater
    Habitations::MediaUpdater.new(
      habitation: @habitation,
      params: params,
      actor: current_admin_user,
      request: request,
      property_setting: @property_setting
    )
  end

  def numeric_param(key)
    value = params[key].to_s.strip
    value.match?(/\A\d+\z/) ? value.to_i : nil
  end

  def respond_with_media_success(message)
    @habitation.reload

    respond_to do |format|
      format.html { redirect_to admin_habitation_media_path(@habitation), notice: message }
      format.json do
        render json: media_response_payload(message: message)
      end
    end
  end

  def respond_with_media_error(message)
    respond_to do |format|
      format.html { redirect_to admin_habitation_media_path(@habitation), alert: message }
      format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
    end
  end

  def respond_with_media_validation_error
    respond_to do |format|
      format.html { render :show, status: :unprocessable_entity }
      format.json { render json: { ok: false, errors: @habitation.errors.full_messages }, status: :unprocessable_entity }
    end
  end

  def media_response_payload(message:)
    gallery_locals = media_gallery_locals
    photos = gallery_locals.fetch(:attached_media_photos)
    pictures = gallery_locals.fetch(:api_media_pictures)
    gallery_count = Habitations::MediaGallery.new(@habitation).media_gallery_count

    {
      ok: true,
      message: message,
      media_url: admin_habitation_media_path(@habitation),
      gallery_html: media_gallery_html(gallery_locals),
      counts: {
        photos: photos.size,
        pictures: pictures.size,
        total: gallery_count
      },
      inputs: {
        ordered_photo_ids: photos.map(&:id).join(","),
        ordered_picture_indices: gallery_locals.fetch(:api_media_pictures).map { |_pic, index, _url| index }.join(","),
        site_hidden_photo_ids: Array(@habitation.site_hidden_photo_ids).map(&:to_i).join(","),
        site_hidden_picture_urls: gallery_locals.fetch(:api_media_pictures)
          .select { |pic, _index, _url| @habitation.picture_hidden_from_site?(pic) }
          .map { |_pic, _index, url| url }
          .join(",")
      },
      photos: photos.map do |attachment|
        {
          id: attachment.id,
          filename: attachment.filename.to_s,
          content_type: attachment.content_type,
          byte_size: attachment.byte_size
        }
      end
    }
  end

  def media_gallery_html(gallery_locals)
    render_to_string(
      partial: "admin/habitations/media/gallery_items",
      formats: [:html],
      locals: gallery_locals
    )
  end

  def media_gallery_locals
    Habitations::MediaGallery.new(@habitation).locals
  end

  def set_habitation
    @habitation = find_admin_habitation_param!(params[:habitation_id])
  end

  def find_admin_habitation_param!(identifier)
    resolve_admin_habitation_param(identifier) || raise(ActiveRecord::RecordNotFound)
  end

  def resolve_admin_habitation_param(identifier)
    identifier = identifier.to_s.strip
    return if identifier.blank?

    if identifier.match?(/\A\d+\z/)
      Habitation.find_by(codigo: identifier) || Habitation.find_by(id: identifier)
    else
      Habitation.friendly.find(identifier)
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def scope_habitation_by_permission
    return if owns_all_resource?(:imoveis)
    return if property_belongs_to_current_user?(@habitation)

    redirect_to admin_habitations_path, alert: "Você não tem acesso a este imóvel."
  end

  def property_belongs_to_current_user?(habitation)
    return false unless current_admin_user
    return true if habitation.admin_user_id == current_admin_user.id
    return true if habitation.broker_assignments.exists?(admin_user_id: current_admin_user.id)

    broker_name = current_admin_user.name.to_s.strip
    broker_name.present? && habitation.corretor_nome.to_s.downcase.include?(broker_name.downcase)
  end

  def load_property_setting
    @property_setting = PropertySetting.instance
  end

  def safe_admin_habitations_return_path(value)
    path = value.to_s.strip
    return nil if path.blank?

    uri = URI.parse(path)
    return nil if uri.scheme.present? || uri.host.present?
    return nil unless uri.path == admin_habitations_path

    [uri.path, uri.query.presence].compact.join("?")
  rescue URI::InvalidURIError
    nil
  end
end
