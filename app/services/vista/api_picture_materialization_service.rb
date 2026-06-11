require "net/http"
require "openssl"
require "stringio"
require "thread"
require "uri"

module Vista
  class ApiPictureMaterializationService
    DEFAULT_BATCH_SIZE = 50
    DEFAULT_WORKERS = 1
    API_FILE_ASSET_DUMP_DIR = "api:vista".freeze
    API_PHOTO_TABLE_NAME = "API_FOTO".freeze
    SOURCE_GALLERY_SQL = <<~SQL.squish.freeze
      (
        jsonb_typeof(habitations.pictures) = 'array'
        AND jsonb_array_length(habitations.pictures) > 0
      )
      OR (
        jsonb_typeof(habitations.fotos_empreendimento) = 'array'
        AND jsonb_array_length(habitations.fotos_empreendimento) > 0
        AND (
          habitations.tipo = 'Empreendimento'
          OR (
            habitations.use_development_photos_flag = TRUE
            AND habitations.codigo_empreendimento IS NOT NULL
            AND habitations.codigo_empreendimento <> ''
          )
        )
      )
    SQL
    SOURCE_IMAGE_COUNT_SQL = <<~SQL.squish.freeze
      CASE
        WHEN jsonb_typeof(habitations.pictures) = 'array' AND jsonb_array_length(habitations.pictures) > 0
          THEN jsonb_array_length(habitations.pictures)
        WHEN jsonb_typeof(habitations.fotos_empreendimento) = 'array'
          AND jsonb_array_length(habitations.fotos_empreendimento) > 0
          AND (
            habitations.tipo = 'Empreendimento'
            OR (
              habitations.use_development_photos_flag = TRUE
              AND habitations.codigo_empreendimento IS NOT NULL
              AND habitations.codigo_empreendimento <> ''
            )
          )
          THEN jsonb_array_length(habitations.fotos_empreendimento)
        ELSE 0
      END
    SQL

    Result = Struct.new(
      :dry_run,
      :replace,
      :workers,
      :properties_scanned,
      :pictures_scanned,
      :reused,
      :downloaded,
      :already_attached,
      :pending_download,
      :detached,
      :failed,
      :errors,
      keyword_init: true
    )

    def initialize(scope: default_scope, dry_run: true, replace: false, limit: nil, batch_size: DEFAULT_BATCH_SIZE, workers: DEFAULT_WORKERS)
      @scope = scope
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @replace = ActiveModel::Type::Boolean.new.cast(replace)
      @limit = limit.to_i.positive? ? limit.to_i : nil
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      requested_workers = workers.to_i.positive? ? workers.to_i : DEFAULT_WORKERS
      @workers = [requested_workers, max_workers_for_connection_pool].min
      @api_file_asset_batch_mutex = Mutex.new
    end

    def call
      result = Result.new(
        dry_run: @dry_run,
        replace: @replace,
        workers: @workers,
        properties_scanned: 0,
        pictures_scanned: 0,
        reused: 0,
        downloaded: 0,
        already_attached: 0,
        pending_download: 0,
        detached: 0,
        failed: 0,
        errors: []
      )

      ids = property_ids
      return result if ids.empty?

      @workers == 1 ? run_sequential(ids, result) : run_parallel(ids, result)
      result
    end

    private

    def self.default_scope
      Habitation
        .where.not(imovel_dwv: "Sim")
        .where(SOURCE_GALLERY_SQL)
    end

    def self.source_image_count_sql
      SOURCE_IMAGE_COUNT_SQL
    end

    def default_scope
      self.class.default_scope
    end

    def property_ids
      @scope.order(:id).limit(@limit).pluck(:id)
    end

    def run_sequential(ids, result)
      ids.each do |habitation_id|
        outcome = process_habitation_id(habitation_id)
        apply_outcome(result, outcome)
      end
    end

    def run_parallel(ids, result)
      queue = Queue.new
      ids.each { |habitation_id| queue << habitation_id }
      mutex = Mutex.new

      threads = Array.new(@workers) do
        Thread.new do
          Thread.current.report_on_exception = false
          ActiveRecord::Base.connection_pool.with_connection do
            loop do
              habitation_id = queue.pop(true)
              outcome = process_habitation_id(habitation_id)
              mutex.synchronize { apply_outcome(result, outcome) }
            rescue ThreadError
              break
            end
          end
        end
      end

      threads.each(&:join)
    end

    def process_habitation_id(habitation_id)
      habitation = Habitation.find(habitation_id)
      outcome = {
        properties_scanned: 1,
        pictures_scanned: 0,
        reused: 0,
        downloaded: 0,
        already_attached: 0,
        pending_download: 0,
        detached: 0,
        failed: 0,
        errors: []
      }
      ordered_attachment_ids = []

      source_pictures_for(habitation).each_with_index do |picture, index|
        url = picture_url(picture)
        next if url.blank?

        outcome[:pictures_scanned] += 1
        filename = filename_from_url(url)
        next if filename.blank?

        asset = upsert_photo_asset(habitation, picture, url, filename, index)

        if (attachment = existing_attachment_by_filename(habitation, filename))
          ordered_attachment_ids << attachment.id
          mark_asset_attached(asset, attachment, reused: true)
          outcome[:already_attached] += 1
          next
        end

        reused_blob = false
        blob = find_reusable_blob(filename)
        if blob
          reused_blob = true
          outcome[:reused] += 1
        elsif @dry_run
          outcome[:pending_download] += 1
          next
        else
          blob = create_blob_from_url(habitation, url, filename)
          outcome[:downloaded] += 1
        end

        unless @dry_run
          attachment = attach_blob_once!(habitation, blob)
          ordered_attachment_ids << attachment.id
          mark_asset_attached(asset, attachment, reused: reused_blob)
        end
      rescue StandardError => e
        mark_asset_failed(asset, e)
        outcome[:failed] += 1
        outcome[:errors] << { codigo: habitation.codigo, url: url, error: e.message }
      end

      if ordered_attachment_ids.any? && !@dry_run
        ordered_attachment_ids = ordered_attachment_ids.uniq
        if @replace
          stale = ActiveStorage::Attachment.where(record: habitation, name: "photos").where.not(id: ordered_attachment_ids)
          outcome[:detached] += stale.count
          stale.destroy_all
        end

        habitation.update!(photo_ids_order: ordered_attachment_ids)
      end

      outcome
    end

    def apply_outcome(result, outcome)
      result.properties_scanned += outcome[:properties_scanned]
      result.pictures_scanned += outcome[:pictures_scanned]
      result.reused += outcome[:reused]
      result.downloaded += outcome[:downloaded]
      result.already_attached += outcome[:already_attached]
      result.pending_download += outcome[:pending_download]
      result.detached += outcome[:detached]
      result.failed += outcome[:failed]
      result.errors.concat(outcome[:errors])
    end

    def max_workers_for_connection_pool
      [ActiveRecord::Base.connection_pool.size - 1, 1].max
    end

    def source_pictures_for(habitation)
      return Array(habitation.pictures) if json_array_present?(habitation.pictures)

      return [] unless json_array_present?(habitation.fotos_empreendimento)
      return Array(habitation.fotos_empreendimento) if habitation.empreendimento? || habitation.use_development_photos?

      []
    end

    def json_array_present?(value)
      value.is_a?(Array) && value.present?
    end

    def api_file_asset_batch
      return @api_file_asset_batch if @api_file_asset_batch

      @api_file_asset_batch_mutex.synchronize do
        @api_file_asset_batch ||= VistaImportBatch.where(dump_dir: API_FILE_ASSET_DUMP_DIR).latest_first.first ||
          VistaImportBatch.create!(dump_dir: API_FILE_ASSET_DUMP_DIR, status: "completed")
      end
    end

    def upsert_photo_asset(habitation, picture, url, filename, index)
      return if @dry_run

      source_path = source_path_from_url(url).presence ||
        ["api", "property_photo", habitation.codigo.presence || habitation.id, filename].join("/")
      asset = VistaFileAsset.find_or_initialize_by(
        vista_import_batch: api_file_asset_batch,
        table_name: API_PHOTO_TABLE_NAME,
        source_path: source_path
      )
      asset.assign_attributes(
        habitation: habitation,
        kind: "property_photo",
        status: asset.status.presence || "pending",
        codigo_imovel: habitation.codigo,
        source_url: url,
        filename: filename,
        active_storage_name: "photos",
        position: picture_position(picture) || index + 1,
        metadata: asset.metadata.to_h.merge("api" => picture)
      )
      asset.save!
      asset
    end

    def source_path_from_url(url)
      URI.parse(url.to_s).path.to_s.delete_prefix("/")
    rescue URI::InvalidURIError
      nil
    end

    def picture_position(picture)
      return unless picture.respond_to?(:[])

      position = picture["ordem"].presence || picture["Ordem"].presence || picture["position"].presence
      position.to_i if position.to_s.match?(/\A\d+\z/)
    end

    def mark_asset_attached(asset, attachment, reused:)
      return if @dry_run || asset.blank?

      blob = attachment.blob
      asset.update!(
        status: "downloaded",
        active_storage_attachment: attachment,
        active_storage_key: blob.key,
        storage_checksum: blob.checksum,
        storage_byte_size: blob.byte_size,
        storage_content_type: blob.content_type,
        storage_service_name: blob.service_name,
        downloaded_at: Time.current,
        reused_at: reused ? Time.current : asset.reused_at,
        error_message: nil
      )
    end

    def mark_asset_failed(asset, error)
      return if @dry_run || asset.blank?

      asset.update!(
        status: "failed",
        attempts: asset.attempts + 1,
        error_message: error.message
      )
    end

    def picture_url(picture)
      return picture.to_s if picture.is_a?(String)
      return unless picture.respond_to?(:[])

      picture["url"].presence ||
        picture["src"].presence ||
        picture["link"].presence ||
        picture["Foto"].presence ||
        picture["FotoOriginal"].presence ||
        picture["FotoPequena"].presence
    end

    def filename_from_url(url)
      File.basename(URI.parse(url.to_s).path)
    rescue URI::InvalidURIError
      File.basename(url.to_s.split("?").first)
    end

    def existing_attachment_by_filename(habitation, filename)
      habitation.photos.attachments.includes(:blob).detect { |attachment| attachment.filename.to_s == filename.to_s }
    end

    def find_reusable_blob(filename)
      ActiveStorage::Blob
        .joins(:attachments)
        .where(active_storage_attachments: { record_type: "Habitation", name: "photos" })
        .where(filename: filename)
        .order(:id)
        .first
    end

    def attach_blob_once!(habitation, blob)
      existing = ActiveStorage::Attachment.find_by(record: habitation, name: "photos", blob: blob)
      return existing if existing

      habitation.photos.attach(blob)
      ActiveStorage::Attachment.find_by!(record: habitation, name: "photos", blob: blob)
    end

    def create_blob_from_url(habitation, url, filename)
      io = download(url)
      body = io.string
      io.rewind

      ActiveStorage::Blob.create_and_upload!(
        key: storage_key_for(habitation, filename),
        io: io,
        filename: filename,
        content_type: Marcel::MimeType.for(StringIO.new(body), name: filename) || "application/octet-stream",
        identify: false,
        metadata: {
          "identified" => true,
          "vista_source_url" => url,
          "vista_codigo" => habitation.codigo
        }
      )
    rescue ActiveRecord::RecordNotUnique
      ActiveStorage::Blob.find_by!(key: storage_key_for(habitation, filename))
    end

    def storage_key_for(habitation, filename)
      ["vista", "property_photo", habitation.codigo.presence || habitation.id, filename].join("/")
    end

    def download(url, read_timeout: 30, open_timeout: 10, max_redirects: 5)
      remaining_redirects = max_redirects

      loop do
        uri = URI.parse(url.to_s)
        raise "URL invalida: #{url.inspect}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
        http.read_timeout = read_timeout
        http.open_timeout = open_timeout

        response = http.request(Net::HTTP::Get.new(uri.request_uri))

        case response
        when Net::HTTPSuccess
          io = StringIO.new(response.body)
          io.set_encoding(Encoding::BINARY)
          return io
        when Net::HTTPRedirection
          raise "Muitos redirects para #{url}" if remaining_redirects <= 0

          remaining_redirects -= 1
          url = response["location"]
        else
          raise "Download falhou (#{response.code} #{response.message}) para #{url}"
        end
      end
    end
  end
end
