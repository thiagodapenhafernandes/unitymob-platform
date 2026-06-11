require "net/http"
require "openssl"
require "digest/md5"
require "base64"
require "stringio"
require "thread"

module Vista
  class FileAssetDownloadService
    DEFAULT_BATCH_SIZE = 50
    DEFAULT_WORKERS = 1

    Result = Struct.new(:dry_run, :workers, :scanned, :downloaded, :reused, :skipped, :failed, :errors, keyword_init: true)

    def initialize(scope: VistaFileAsset.pending, dry_run: true, limit: nil, batch_size: DEFAULT_BATCH_SIZE, workers: DEFAULT_WORKERS)
      @scope = scope
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @limit = limit.to_i.positive? ? limit.to_i : nil
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      requested_workers = workers.to_i.positive? ? workers.to_i : DEFAULT_WORKERS
      @workers = [requested_workers, max_workers_for_connection_pool].min
    end

    def call
      result = Result.new(dry_run: @dry_run, workers: @workers, scanned: 0, downloaded: 0, reused: 0, skipped: 0, failed: 0, errors: [])
      ids = asset_ids
      return result if ids.empty?

      @workers == 1 ? run_sequential(ids, result) : run_parallel(ids, result)

      result
    end

    private

    def asset_ids
      @scope.order(:id).limit(@limit).pluck(:id)
    end

    def run_sequential(ids, result)
      ids.each do |asset_id|
        outcome = process_asset_id(asset_id)
        apply_outcome(result, outcome)
      end
    end

    def run_parallel(ids, result)
      queue = Queue.new
      ids.each { |asset_id| queue << asset_id }
      mutex = Mutex.new

      threads = Array.new(@workers) do
        Thread.new do
          Thread.current.report_on_exception = false
          ActiveRecord::Base.connection_pool.with_connection do
            loop do
              asset_id = queue.pop(true)
              outcome = process_asset_id(asset_id)
              mutex.synchronize { apply_outcome(result, outcome) }
            rescue ThreadError
              break
            end
          end
        end
      end

      threads.each(&:join)
    end

    def process_asset_id(asset_id)
      asset = VistaFileAsset.find(asset_id)

      unless attachable?(asset)
        mark_skipped(asset) unless @dry_run
        return { status: :skipped }
      end

      if (attachment = already_attached_attachment(asset))
        mark_attached(asset, attachment, status: "downloaded") unless @dry_run
        return { status: :skipped }
      end

      return { status: :downloaded } if @dry_run

      if reusable_storage_object?(asset)
        attach_reused_asset(asset)
        { status: :reused }
      else
        download_and_attach_asset(asset)
        { status: :downloaded }
      end
    rescue StandardError => e
      mark_failed(asset, e) if defined?(asset) && asset
      { status: :failed, asset_id: asset_id, source_url: asset&.source_url, error: e.message }
    end

    def apply_outcome(result, outcome)
      result.scanned += 1

      case outcome[:status]
      when :downloaded
        result.downloaded += 1
      when :reused
        result.reused += 1
      when :skipped
        result.skipped += 1
      when :failed
        result.failed += 1
        result.errors << { asset_id: outcome[:asset_id], source_url: outcome[:source_url], error: outcome[:error] }
      end
    end

    def max_workers_for_connection_pool
      # Keep one connection available for the main thread and framework internals.
      [ActiveRecord::Base.connection_pool.size - 1, 1].max
    end

    def attachable?(asset)
      asset.habitation.present? && asset.active_storage_name.present? && asset.source_url.present?
    end

    def already_attached_attachment(asset)
      return false unless asset.habitation

      attachment_name = asset.active_storage_name
      return false unless asset.habitation.respond_to?(attachment_name)

      asset.habitation.public_send(attachment_name).attachments.includes(:blob).detect do |attachment|
        attachment.blob.key == storage_key_for(asset) || attachment.filename.to_s == asset.filename
      end
    end

    def reusable_storage_object?(asset)
      service.exist?(storage_key_for(asset))
    end

    def attach_reused_asset(asset)
      blob = find_or_create_blob_for_existing_object(asset)
      attachment = attach_blob(asset, blob)

      asset.update!(
        status: "downloaded",
        active_storage_attachment: attachment,
        active_storage_key: blob.key,
        storage_checksum: blob.checksum,
        storage_byte_size: blob.byte_size,
        storage_content_type: blob.content_type,
        storage_service_name: blob.service_name,
        attempts: asset.attempts + 1,
        reused_at: Time.current,
        downloaded_at: Time.current,
        error_message: nil
      )
    end

    def download_and_attach_asset(asset)
      io = download(asset.source_url)
      detected_content_type = content_type_for(asset, io)
      io.rewind
      blob = upload_or_reuse_blob(asset, io, detected_content_type)
      attachment = attach_blob(asset, blob)

      asset.update!(
        status: "downloaded",
        active_storage_attachment: attachment,
        active_storage_key: blob.key,
        storage_checksum: blob.checksum,
        storage_byte_size: blob.byte_size,
        storage_content_type: blob.content_type,
        storage_service_name: blob.service_name,
        attempts: asset.attempts + 1,
        downloaded_at: Time.current,
        error_message: nil
      )
    end

    def attach_blob(asset, blob)
      ActiveStorage::Attachment.find_or_create_by!(
        record: asset.habitation,
        name: asset.active_storage_name,
        blob: blob
      )
    end

    def upload_or_reuse_blob(asset, io, content_type)
      key = storage_key_for(asset)
      existing_blob = ActiveStorage::Blob.find_by(key: key)
      return sync_existing_blob(asset, existing_blob, io, content_type) if existing_blob

      ActiveStorage::Blob.create_and_upload!(
        key: key,
        io: io,
        filename: asset.filename,
        content_type: content_type,
        identify: false,
        metadata: storage_metadata_for(asset),
        service_name: service_name
      )
    rescue ActiveRecord::RecordNotUnique
      sync_existing_blob(asset, ActiveStorage::Blob.find_by!(key: key), io, content_type)
    end

    def sync_existing_blob(asset, blob, io, content_type)
      body = io.string
      checksum = checksum_for(body)
      byte_size = body.bytesize

      unless service.exist?(blob.key)
        upload_io = StringIO.new(body)
        upload_io.set_encoding(Encoding::BINARY)
        service.upload(blob.key, upload_io, checksum: checksum)
      end

      blob.update!(
        filename: asset.filename,
        byte_size: byte_size,
        checksum: checksum,
        content_type: content_type,
        metadata: storage_metadata_for(asset),
        service_name: service_name
      )

      blob
    end

    def find_or_create_blob_for_existing_object(asset)
      key = storage_key_for(asset)
      ActiveStorage::Blob.find_by(key: key) || begin
        checksum, byte_size = reusable_object_metadata(asset)
        ActiveStorage::Blob.create_before_direct_upload!(
          key: key,
          filename: asset.filename,
          byte_size: byte_size,
          checksum: checksum,
          content_type: asset.storage_content_type || content_type_for(asset),
          metadata: storage_metadata_for(asset),
          service_name: asset.storage_service_name || service_name
        )
      end
    end

    def reusable_object_metadata(asset)
      return [asset.storage_checksum, asset.storage_byte_size] if asset.storage_checksum.present? && asset.storage_byte_size.present?

      body = service.download(storage_key_for(asset))
      [checksum_for(body), body.bytesize]
    end

    def mark_attached(asset, attachment, status:)
      blob = attachment.blob
      asset.update!(
        status: status,
        active_storage_attachment: attachment,
        active_storage_key: blob.key,
        storage_checksum: blob.checksum,
        storage_byte_size: blob.byte_size,
        storage_content_type: blob.content_type,
        storage_service_name: blob.service_name,
        attempts: asset.attempts + 1,
        downloaded_at: Time.current,
        error_message: nil
      )
    end

    def mark_skipped(asset)
      asset.update!(status: "skipped", attempts: asset.attempts + 1)
    end

    def mark_failed(asset, error)
      asset.update!(
        status: "failed",
        attempts: asset.attempts + 1,
        error_message: error.message
      )
    end

    def storage_key_for(asset)
      asset.active_storage_key.presence || [
        "vista",
        asset.kind,
        asset.codigo_imovel.presence || asset.codigo_cliente.presence || asset.codigo_corretor.presence || "sem_codigo",
        "#{asset.id}-#{asset.filename}"
      ].join("/")
    end

    def storage_metadata_for(asset)
      {
        "analyzed" => true,
        "identified" => true,
        "vista_file_asset_id" => asset.id,
        "vista_import_batch_id" => asset.vista_import_batch_id,
        "vista_table_name" => asset.table_name,
        "vista_source_path" => asset.source_path,
        "vista_source_url" => asset.source_url
      }
    end

    def service
      ActiveStorage::Blob.service
    end

    def service_name
      ActiveStorage::Blob.service.name
    end

    def content_type_for(asset, io = nil)
      asset.storage_content_type.presence ||
        Marcel::MimeType.for(io || StringIO.new(""), name: asset.filename) ||
        "application/octet-stream"
    end

    def checksum_for(body)
      Base64.strict_encode64(Digest::MD5.digest(body))
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
