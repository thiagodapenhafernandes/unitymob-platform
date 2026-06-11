class Admin::ImageMigrationStatusController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }

  PUBLIC_STATUSES = ["Venda", "Aluguel"].freeze
  CONFIG_PREFIX = "image_migration.".freeze
  API_FILE_ASSET_DUMP_DIR = "api:vista".freeze
  SYNC_MODES = {
    "missing_properties" => "Somente imóveis pendentes",
    "full_scan" => "Varrer todos os imóveis"
  }.freeze
  DEFAULT_CONFIGURATION = {
    "mode" => "missing_properties",
    "batch_size" => "100",
    "workers" => "4",
    "replace" => "false",
    "dry_run" => "false"
  }.freeze

  def index
    @status = build_status
    @configuration = image_migration_configuration

    respond_to do |format|
      format.html
      format.json { render json: @status }
    end
  end

  def update_configuration
    config = normalized_configuration(configuration_params)

    config.each do |key, value|
      Setting.set("#{CONFIG_PREFIX}#{key}", value, image_migration_setting_description(key))
    end

    redirect_to admin_image_migration_status_path, notice: "Configurações da migração de imagens salvas."
  rescue => e
    redirect_to admin_image_migration_status_path, alert: "Erro ao salvar configurações: #{e.message}"
  end

  def sync
    if worker_status[:running]
      redirect_to admin_image_migration_status_path, alert: "A migração de imagens já está rodando."
      return
    end

    configuration = image_migration_configuration
    start_images_sync!(configuration)

    redirect_to admin_image_migration_status_path, notice: "Migração de imagens iniciada em segundo plano com as configurações salvas."
  rescue => e
    redirect_to admin_image_migration_status_path, alert: "Falha ao iniciar migração de imagens: #{e.message}"
  end

  def retry_failed
    if worker_status[:running]
      redirect_to admin_image_migration_status_path, alert: "A migração de imagens já está rodando."
      return
    end

    start_failed_retry!

    redirect_to admin_image_migration_status_path, notice: "Retry dos imóveis com falha iniciado em segundo plano."
  rescue => e
    redirect_to admin_image_migration_status_path, alert: "Falha ao iniciar retry: #{e.message}"
  end

  private

  def build_status
    source_scope = api_picture_source_scope

    total_properties = source_scope.count
    properties_with_photos = source_scope.joins(:photos_attachments).distinct.count
    pending_properties = source_scope.where.missing(:photos_attachments).count
    public_pending_properties = source_scope.where(status: PUBLIC_STATUSES).where.missing(:photos_attachments).count
    public_vista_first_properties = public_vista_first_scope.count
    total_source_images = source_scope.pick(Arel.sql("COALESCE(SUM(#{Vista::ApiPictureMaterializationService.source_image_count_sql}), 0)::bigint")).to_i
    migrated_images = ActiveStorage::Attachment.where(record_type: "Habitation", name: "photos").count
    latest_attachment_at = ActiveStorage::Attachment.where(record_type: "Habitation", name: "photos").maximum(:created_at)
    worker = worker_status
    file_asset_counts = api_photo_file_asset_counts
    failed_ids = api_photo_failed_habitation_ids

    {
      total_properties: total_properties,
      properties_with_photos: properties_with_photos,
      pending_properties: pending_properties,
      public_pending_properties: public_pending_properties,
      public_vista_first_properties: public_vista_first_properties,
      public_vista_first_sample: public_vista_first_scope.limit(20).pluck(:id),
      property_progress: percentage(properties_with_photos, total_properties),
      total_source_images: total_source_images,
      migrated_images: migrated_images,
      image_progress: percentage([migrated_images, total_source_images].min, total_source_images),
      failed_properties: failed_ids.size,
      failed_sample: failed_ids.first(20),
      worker: worker,
      latest_attachment_at: latest_attachment_at,
      file_asset_counts: file_asset_counts,
      downloaded_file_assets: file_asset_counts.fetch("downloaded", 0),
      pending_file_assets: file_asset_counts.fetch("pending", 0),
      failed_file_assets: file_asset_counts.fetch("failed", 0),
      execution: execution_status(
        worker: worker,
        pending_properties: pending_properties,
        properties_with_photos: properties_with_photos,
        migrated_images: migrated_images
      ),
      paths: {
        log: log_file.to_s
      }
    }
  end

  def percentage(current, total)
    return 100.0 if total.to_i.zero?

    ((current.to_f / total.to_f) * 100).round(2)
  end

  def public_vista_first_scope
    api_picture_source_scope
      .where(exibir_no_site_flag: true)
      .where(status: PUBLIC_STATUSES)
      .where.missing(:photos_attachments)
  end

  def api_picture_source_scope
    Vista::ApiPictureMaterializationService.default_scope
  end

  def worker_status
    pid = read_integer(pid_file)
    running = pid.present? && process_running?(pid)
    cleanup_stale_pid_file(pid) if pid.present? && !running

    {
      running: running,
      pid: running ? pid : nil,
      status: running ? "Rodando" : "Parado"
    }
  end

  def cleanup_stale_pid_file(pid)
    return unless pid_file.exist?
    return unless read_integer(pid_file) == pid

    pid_file.delete
  rescue
    nil
  end

  def process_running?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  rescue
    false
  end

  def api_photo_file_assets
    VistaFileAsset
      .joins(:vista_import_batch)
      .where(
        vista_import_batches: { dump_dir: API_FILE_ASSET_DUMP_DIR },
        kind: "property_photo"
      )
  end

  def api_photo_file_asset_counts
    api_photo_file_assets.group(:status).count.transform_keys(&:to_s)
  end

  def api_photo_failed_habitation_ids
    api_photo_file_assets.where(status: "failed").where.not(habitation_id: nil).distinct.limit(1000).pluck(:habitation_id)
  rescue
    []
  end

  def read_integer(path, pattern = /\A\s*(\d+)\s*\z/)
    return nil unless path.exist?

    content = path.read
    match = content.match(pattern)
    match ? match[1].to_i : nil
  rescue
    nil
  end

  def start_images_sync!(configuration)
    FileUtils.mkdir_p(shared_tmp)
    FileUtils.mkdir_p(shared_log)
    record_run_start!(configuration)

    env = {
      "RAILS_ENV" => Rails.env,
      "BATCH_SIZE" => configuration.fetch("batch_size"),
      "WORKERS" => configuration.fetch("workers"),
      "ONLY_WITHOUT_ATTACHED" => only_without_attachments_for(configuration.fetch("mode")),
      "REPLACE" => configuration.fetch("replace"),
      "DRY_RUN" => configuration.fetch("dry_run")
    }

    spawn_rake!(env, "vista_files:materialize_api_photos")
  end

  def start_failed_retry!
    FileUtils.mkdir_p(shared_tmp)
    FileUtils.mkdir_p(shared_log)

    configuration = image_migration_configuration
    record_run_start!(configuration.merge("mode" => "retry_failed"))
    env = {
      "RAILS_ENV" => Rails.env,
      "BATCH_SIZE" => configuration.fetch("batch_size"),
      "WORKERS" => configuration.fetch("workers"),
      "ONLY_WITHOUT_ATTACHED" => "false",
      "REPLACE" => "false",
      "DRY_RUN" => configuration.fetch("dry_run")
    }

    spawn_rake!(env, "vista_files:materialize_api_photos")
  end

  def spawn_rake!(env, task_name)
    pid = Process.spawn(env, Gem.ruby, "-S", "bundle", "exec", "rake", task_name,
      chdir: Rails.root.to_s,
      out: [log_file.to_s, "a"],
      err: [:child, :out],
      pgroup: true)

    pid_file.write(pid.to_s)
    Process.detach(pid)
  end

  def record_run_start!(configuration)
    status = build_status_for_run_start
    values = {
      "mode" => configuration.fetch("mode"),
      "started_at" => Time.current.iso8601,
      "initial_pending_properties" => status.fetch(:pending_properties).to_s,
      "initial_properties_with_photos" => status.fetch(:properties_with_photos).to_s,
      "initial_migrated_images" => status.fetch(:migrated_images).to_s,
      "initial_downloaded_file_assets" => status.fetch(:downloaded_file_assets).to_s
    }

    values.each do |key, value|
      Setting.set("#{CONFIG_PREFIX}run.#{key}", value, "Estado da execução atual da migração de imagens")
    end
  end

  def build_status_for_run_start
    source_scope = api_picture_source_scope

    {
      pending_properties: source_scope.where.missing(:photos_attachments).count,
      properties_with_photos: source_scope.joins(:photos_attachments).distinct.count,
      migrated_images: ActiveStorage::Attachment.where(record_type: "Habitation", name: "photos").count,
      downloaded_file_assets: api_photo_file_asset_counts.fetch("downloaded", 0)
    }
  end

  def execution_status(worker:, pending_properties:, properties_with_photos:, migrated_images:)
    mode = Setting.get("#{CONFIG_PREFIX}run.mode", image_migration_configuration.fetch("mode"))
    started_at = Setting.get("#{CONFIG_PREFIX}run.started_at")
    initial_pending = Setting.get("#{CONFIG_PREFIX}run.initial_pending_properties", pending_properties.to_s).to_i
    initial_properties_with_photos = Setting.get("#{CONFIG_PREFIX}run.initial_properties_with_photos", properties_with_photos.to_s).to_i
    initial_migrated_images = Setting.get("#{CONFIG_PREFIX}run.initial_migrated_images", migrated_images.to_s).to_i

    progress_payload = if mode == "missing_properties" && initial_pending.positive?
      current = (initial_pending - pending_properties).clamp(0, initial_pending)
      {
        label: "Imóveis faltantes migrados nesta execução",
        current: current,
        total: initial_pending,
        remaining: pending_properties,
        progress: percentage(current, initial_pending)
      }
    else
      current = [properties_with_photos - initial_properties_with_photos, 0].max
      total = [current + pending_properties, 1].max
      {
        label: "Fotos materializadas nesta execução",
        current: current,
        total: total,
        remaining: pending_properties,
        progress: percentage(current, total)
      }
    end

    {
      mode: mode,
      running: worker[:running],
      started_at: started_at,
      last_run_at: latest_attachment_timestamp,
      synced: [properties_with_photos - initial_properties_with_photos, 0].max,
      failed: api_photo_file_asset_counts.fetch("failed", 0),
      properties_added: [properties_with_photos - initial_properties_with_photos, 0].max,
      images_added: [migrated_images - initial_migrated_images, 0].max
    }.merge(progress_payload)
  end

  def latest_attachment_timestamp
    ActiveStorage::Attachment.where(record_type: "Habitation", name: "photos").maximum(:created_at)
  end

  def image_migration_configuration
    DEFAULT_CONFIGURATION.each_with_object({}) do |(key, default_value), configuration|
      configuration[key] = Setting.get("#{CONFIG_PREFIX}#{key}", default_value).to_s
    end
  end

  def normalized_configuration(raw_params)
    {
      "mode" => SYNC_MODES.key?(raw_params[:mode]) ? raw_params[:mode] : DEFAULT_CONFIGURATION.fetch("mode"),
      "batch_size" => clamp_integer(raw_params[:batch_size], 1, 500, DEFAULT_CONFIGURATION.fetch("batch_size")),
      "workers" => clamp_integer(raw_params[:workers], 1, 8, DEFAULT_CONFIGURATION.fetch("workers")),
      "replace" => boolean_string(raw_params[:replace]),
      "dry_run" => boolean_string(raw_params[:dry_run])
    }
  end

  def clamp_integer(value, min, max, default)
    integer = Integer(value.to_s, exception: false)
    integer = default.to_i if integer.nil?
    integer.clamp(min, max).to_s
  end

  def boolean_string(value)
    ActiveModel::Type::Boolean.new.cast(value).to_s
  end

  def only_without_attachments_for(mode)
    (mode == "missing_properties").to_s
  end

  def image_migration_setting_description(key)
    {
      "mode" => "Modo de execução da migração de imagens",
      "batch_size" => "Quantidade de imóveis por lote da migração de imagens",
      "workers" => "Quantidade de threads da migração de imagens",
      "replace" => "Substitui anexos que nao fazem parte da galeria API/Vista",
      "dry_run" => "Simula a migração de imagens sem anexar arquivos"
    }[key]
  end

  def configuration_params
    params.require(:image_migration).permit(
      :mode,
      :batch_size,
      :workers,
      :replace,
      :dry_run
    )
  end

  def pid_file
    shared_tmp.join("api_pictures_materialization.pid")
  end

  def log_file
    shared_log.join("api_pictures_materialization.log")
  end

  def shared_tmp
    configured_shared_path("SPACES_IMAGE_SYNC_SHARED_TMP", "/home/salute/deploy/shared/tmp", Rails.root.join("tmp"))
  end

  def shared_log
    configured_shared_path("SPACES_IMAGE_SYNC_SHARED_LOG", "/home/salute/deploy/shared/log", Rails.root.join("log"))
  end

  def configured_shared_path(env_key, production_path, fallback_path)
    configured = ENV[env_key].presence
    return Pathname.new(configured) if configured

    production = Pathname.new(production_path)
    production.exist? ? production : Pathname.new(fallback_path)
  end
end
