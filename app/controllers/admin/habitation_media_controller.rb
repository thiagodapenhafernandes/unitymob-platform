class Admin::HabitationMediaController < Admin::BaseController
  RETURN_PARAM_DENYLIST = %w[
    controller action id habitation_id return_to back_anchor authenticity_token _method utf8 commit
    habitation save_anchor save_navigation save_context
  ].freeze

  before_action -> { check_permission!(:view, :imoveis) }
  before_action :set_habitation
  before_action :scope_habitation_by_permission
  before_action :load_property_setting

  def show
    @page_title = "Mídia do Imóvel: #{@habitation.codigo}"
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])
    @media_tools_can_edit = can_manage_media_tools?
    @media_tools_ambientes = Habitation::FOTO_AMBIENTES
  end

  def modal
    @return_to_path = safe_admin_habitations_return_path(params[:return_to])

    render partial: "admin/habitations/media/modal_content",
           layout: false,
           locals: {
             habitation: @habitation,
             return_to_path: @return_to_path,
             can_edit_media: can_manage_media_tools?
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
          redirect_to admin_path_with_flat_return(admin_habitation_media_path(@habitation.id), @return_to_path),
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

  # PATCH /admin/habitations/:habitation_id/media/ambiente
  # Grava o ambiente da foto. Para ActiveStorage usa blob.metadata; para fotos
  # externas (DWV/API) grava no próprio payload de pictures.
  def ambiente
    return render_media_forbidden unless can_manage_media_tools?

    photo_id = numeric_param(:photo_id) || media_tools_param_id(:photo_id)
    picture_index = numeric_param(:picture_index) || media_tools_param_id(:picture_index)
    if photo_id.blank? && picture_index.blank?
      respond_with_media_error("Informe a foto que deve receber o ambiente.")
      return
    end

    ambiente_value = params.dig(:habitation, :ambiente).to_s.strip
    if ambiente_value.present? && !Habitation::FOTO_AMBIENTES.include?(ambiente_value)
      respond_with_media_error("Ambiente inválido.")
      return
    end

    if photo_id.present?
      attachment = @habitation.photos.attachments.includes(:blob).find_by(id: photo_id)
      if attachment.blank?
        respond_with_media_error("Foto não encontrada.")
        return
      end

      @habitation.set_photo_ambiente!(
        attachment,
        ambiente_value,
        position: params.dig(:habitation, :ambiente_position)
      )
    elsif !@habitation.set_picture_ambiente!(
      picture_index,
      ambiente_value,
      position: params.dig(:habitation, :ambiente_position)
    )
      respond_with_media_error("Foto externa não encontrada.")
      return
    end

    respond_with_media_success("Ambiente atualizado.")
  end

  # POST /admin/habitations/:habitation_id/media/organize
  # Reordena as fotos pela ordem canônica de ambientes. Re-renderiza a galeria.
  def organize
    return render_media_forbidden unless can_manage_media_tools?

    @habitation.organize_photos_by_ambiente!
    respond_with_media_success("Fotos organizadas por ambiente.")
  end

  # POST /admin/habitations/:habitation_id/media/share
  # Gera um link público com as fotos selecionadas + URL de WhatsApp.
  def share
    return render_media_forbidden unless can_manage_media_tools?

    photo_ids = share_photo_ids_param
    if photo_ids.blank?
      respond_with_media_error("Selecione ao menos uma foto para enviar.")
      return
    end

    valid_ids = @habitation.photos.attachments.where(id: photo_ids).ids
    if valid_ids.blank?
      respond_with_media_error("Nenhuma das fotos selecionadas está disponível.")
      return
    end

    share = HabitationPhotoShare.create_for(
      habitation: @habitation,
      admin_user: current_admin_user,
      photo_ids: valid_ids
    )

    share_url = habitation_photo_share_url(share.token)
    whatsapp_text = "Confira as fotos do imóvel #{@habitation.codigo}: #{share_url}"

    render json: {
      ok: true,
      share_url: share_url,
      whatsapp_url: "https://wa.me/?text=#{ERB::Util.url_encode(whatsapp_text)}"
    }
  end

  private

  def can_manage_media_tools?
    return false unless current_admin_user
    return false unless current_admin_user.can?(:media, :imoveis) || current_admin_user.can?(:manage, :imoveis)
    return true if owns_all_resource?(:imoveis)
    return true if property_belongs_to_current_user?(@habitation)
    return true if current_admin_user&.can_view_team?(:imoveis) && property_owned_by_team?(@habitation)

    catalog_media_visible?(@habitation)
  end

  def render_media_forbidden
    respond_to do |format|
      format.json { render json: { ok: false, error: "forbidden" }, status: :forbidden }
      format.html { redirect_to admin_habitation_media_path(@habitation.id), alert: "Você não tem permissão para editar as fotos deste imóvel." }
    end
  end

  def media_tools_param_id(key)
    value = params.dig(:habitation, key).to_s.strip
    value.match?(/\A\d+\z/) ? value.to_i : nil
  end

  def share_photo_ids_param
    raw = params.dig(:habitation, :photo_ids)
    Array(raw)
      .flat_map { |id| id.to_s.split(",") }
      .map(&:strip)
      .select { |id| id.match?(/\A\d+\z/) }
      .map(&:to_i)
      .uniq
  end

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
      format.html { redirect_to admin_habitation_media_path(@habitation.id), notice: message }
      format.json do
        render json: media_response_payload(message: message)
      end
    end
  end

  def respond_with_media_error(message)
    respond_to do |format|
      format.html { redirect_to admin_habitation_media_path(@habitation.id), alert: message }
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
      media_url: admin_habitation_media_path(@habitation.id),
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
    # can_edit_media explícito no re-render (ambiente/organize): o partial tem
    # fallback, mas passamos para garantir engrenagem/checkbox/ambiente pós-ação.
    Habitations::MediaGallery.new(@habitation).locals.merge(
      can_edit_media: can_manage_media_tools?
    )
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
      current_tenant.habitations.find_by(id: identifier) || current_tenant.habitations.find_by(codigo: identifier)
    else
      current_tenant.habitations.friendly.find(identifier)
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def scope_habitation_by_permission
    return if can_manage_media_tools?

    redirect_to admin_habitations_path, alert: "Você não tem acesso a este imóvel."
  end

  def property_owned_by_team?(habitation)
    ids = current_admin_user.team_scope_ids
    return true if ids.include?(habitation.admin_user_id)

    habitation.broker_assignments.exists?(admin_user_id: ids)
  end

  def property_belongs_to_current_user?(habitation)
    return false unless current_admin_user
    return true if habitation.admin_user_id == current_admin_user.id
    return true if habitation.broker_assignments.exists?(admin_user_id: current_admin_user.id)

    broker_name = current_admin_user.name.to_s.strip
    broker_name.present? && habitation.corretor_nome.to_s.downcase.include?(broker_name.downcase)
  end

  def catalog_media_visible?(habitation)
    return false unless habitation
    return false if current_tenant.present? && habitation.tenant_id != current_tenant.id
    return true unless habitation.broker_intake?

    Habitation::CATALOG_VISIBLE_INTAKE_STATUSES.include?(habitation.intake_status)
  end

  def load_property_setting
    @property_setting = PropertySetting.instance
  end

  def safe_admin_habitations_return_path(value, source_params: params)
    path = value.to_s.strip
    return nil if path.blank?

    uri = URI.parse(path)
    return nil if uri.scheme.present? || uri.host.present?
    return nil unless uri.path == admin_habitations_path

    query_params = Rack::Utils.parse_nested_query(uri.query.to_s)
    query_params.merge!(flattened_admin_habitations_return_query_params(source_params))
    query = Rack::Utils.build_nested_query(query_params.compact_blank)
    path_with_query = [uri.path, query.presence].compact.join("?")
    fragment = uri.fragment.presence || source_params[:back_anchor].to_s.presence || source_params["back_anchor"].to_s.presence
    fragment.present? ? "#{path_with_query}##{fragment}" : path_with_query
  rescue URI::InvalidURIError
    nil
  end

  def admin_path_with_flat_return(path, return_to)
    helpers.admin_habitation_path_with_query(
      path,
      helpers.admin_habitation_flat_return_params(return_to)
    )
  end

  def flattened_admin_habitations_return_query_params(source_params)
    raw_params =
      if source_params.respond_to?(:to_unsafe_h)
        source_params.to_unsafe_h
      else
        source_params.to_h
      end

    raw_params
      .except(*RETURN_PARAM_DENYLIST)
      .compact_blank
  end
end
