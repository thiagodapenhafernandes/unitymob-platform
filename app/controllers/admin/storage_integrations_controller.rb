class Admin::StorageIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }
  before_action :load_setting

  def show
    prepare_show_state
  end

  def update
    assign_storage_attributes

    if @storage_setting.save
      Storage::ActiveStorageRegistry.register!(@storage_setting)
      redirect_to admin_storage_integration_path, notice: "Configurações de armazenamento salvas com sucesso."
    else
      prepare_show_state
      render :show, status: :unprocessable_entity
    end
  end

  def test_connection
    assign_storage_attributes

    unless params[:provider].to_s == "local" || @storage_setting.valid?
      prepare_show_state
      render :show, status: :unprocessable_entity
      return
    end

    result = Storage::ConnectionTester.new(setting: @storage_setting, provider: params[:provider]).call
    @storage_setting.save! if @storage_setting.valid?
    @storage_setting.mark_test!(status: result.ok? ? "success" : "failed", message: result.message)

    if result.ok?
      redirect_to admin_storage_integration_path, notice: result.message
    else
      redirect_to admin_storage_integration_path, alert: result.message
    end
  end

  def publish_public_photos
    publish_needed_public_photos
  end

  def publish_needed_public_photos
    stats = Storage::PublicPropertyPhotoPublisher.stats
    Storage::PublicPropertyPhotoPublisher.write_progress(
      status: "queued",
      total: stats.total_attachments,
      processed: 0,
      published: 0,
      failed: 0,
      skipped: 0,
      percent: 0,
      message: "Publicação enfileirada. Aguardando o worker iniciar.",
      started_at: Time.current,
      finished_at: nil
    )

    Storage::PublishPublicPropertyPhotosJob.perform_later(current_admin_user&.id)

    redirect_to admin_storage_integration_path(pending_public_photos: "1"),
                notice: "Publicação das fotos públicas iniciada. Acompanhe o progresso nesta tela."
  end

  def public_photo_publish_status
    render json: Storage::PublicPropertyPhotoPublisher.progress
  end

  def publish_attachment
    result = Storage::PublicPropertyPhotoPublisher.new.publish_attachment_id(params[:attachment_id])
    redirect_with_publish_result(result, "attachment")
  end

  def publish_habitation_photos
    result = Storage::PublicPropertyPhotoPublisher.new.publish_habitation_id(params[:habitation_id])
    redirect_with_publish_result(result, "imóvel")
  end

  def publish_blob
    result = Storage::PublicPropertyPhotoPublisher.new.publish_blob_id(params[:blob_id])
    redirect_with_publish_result(result, "blob")
  end

  private

  def load_setting
    @storage_setting = StorageIntegrationSetting.current
  end

  def prepare_show_state
    @public_photo_stats = Storage::PublicPropertyPhotoPublisher.stats
    @public_photo_publish_last_result = Storage::PublicPropertyPhotoPublisher.last_result
    @public_photo_publish_progress = Storage::PublicPropertyPhotoPublisher.progress
    @public_photo_lookup = Storage::PublicPropertyPhotoPublisher.lookup(params[:photo_lookup])
    @public_photo_pending_summary = Storage::PublicPropertyPhotoPublisher.pending_summary if params[:pending_public_photos].present?
  end

  def redirect_with_publish_result(result, label)
    message = Storage::PublicPropertyPhotoPublisher.result_message(result)
    details = result.errors.first(3).join(" | ")
    flash_key = result.ok? ? :notice : :alert
    redirect_params = params[:photo_lookup].present? ? { photo_lookup: params[:photo_lookup] } : {}

    redirect_to admin_storage_integration_path(redirect_params), flash_key => ["Publicação por #{label}: #{message}", details.presence].compact.join(". ")
  end

  def assign_storage_attributes
    @storage_setting.assign_attributes(normalized_storage_params)

    permitted_storage_params.slice(
      :do_spaces_access_key_id,
      :do_spaces_secret_access_key,
      :s3_access_key_id,
      :s3_secret_access_key
    ).each do |attribute, value|
      next if value.to_s.blank?

      @storage_setting.public_send("#{attribute}=", value)
    end
  end

  def normalized_storage_params
    permitted_storage_params.except(
      :do_spaces_access_key_id,
      :do_spaces_secret_access_key,
      :s3_access_key_id,
      :s3_secret_access_key
    ).tap do |attributes|
      normalize_digital_ocean_defaults(attributes)
      normalize_amazon_defaults(attributes)
    end
  end

  def normalize_digital_ocean_defaults(attributes)
    return unless [attributes[:photo_provider], attributes[:document_provider]].include?("digital_ocean")

    attributes[:do_spaces_bucket] = attributes[:do_spaces_bucket].presence || @storage_setting.do_spaces_bucket.presence || ENV["DO_SPACES_BUCKET"].presence
    attributes[:do_spaces_region] = attributes[:do_spaces_region].presence || @storage_setting.do_spaces_region.presence || ENV.fetch("DO_SPACES_REGION", "sfo3")
    attributes[:do_spaces_endpoint] = attributes[:do_spaces_endpoint].presence || @storage_setting.do_spaces_endpoint.presence || ENV.fetch("DO_SPACES_ENDPOINT", "https://sfo3.digitaloceanspaces.com")
  end

  def normalize_amazon_defaults(attributes)
    return unless [attributes[:photo_provider], attributes[:document_provider]].include?("amazon_s3")

    attributes[:s3_bucket] = attributes[:s3_bucket].presence || @storage_setting.s3_bucket.presence || ENV["AWS_S3_BUCKET"].presence || ENV["S3_BUCKET"].presence
    attributes[:s3_region] = attributes[:s3_region].presence || @storage_setting.s3_region.presence || ENV.fetch("AWS_REGION", ENV.fetch("S3_REGION", "us-east-1"))
  end

  def permitted_storage_params
    params.fetch(:storage_integration_setting, {}).permit(
      :photo_provider,
      :document_provider,
      :public_photos_enabled,
      :do_spaces_bucket,
      :do_spaces_region,
      :do_spaces_endpoint,
      :do_spaces_public_base_url,
      :s3_bucket,
      :s3_region,
      :s3_endpoint,
      :s3_public_base_url,
      :do_spaces_access_key_id,
      :do_spaces_secret_access_key,
      :s3_access_key_id,
      :s3_secret_access_key
    )
  end
end
