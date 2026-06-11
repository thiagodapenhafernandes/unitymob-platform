require "net/http"
require "openssl"
require "digest/md5"
require "base64"
require "stringio"

module Vista
  class AgentAvatarDownloadService
    BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/".freeze

    Result = Struct.new(:scanned, :downloaded, :skipped, :failed, :errors, keyword_init: true)

    def initialize(scope: AdminUser.where.not(source_photo_path: [nil, ""]), dry_run: false)
      @scope = scope
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
    end

    def call
      result = Result.new(scanned: 0, downloaded: 0, skipped: 0, failed: 0, errors: [])

      @scope.find_each do |user|
        result.scanned += 1

        if avatar_available?(user)
          result.skipped += 1
          next
        end

        if @dry_run
          result.downloaded += 1
          next
        end

        attach_avatar(user)
        result.downloaded += 1
      rescue StandardError => e
        result.failed += 1
        result.errors << { admin_user_id: user.id, email: user.email, source_photo_path: user.source_photo_path, error: e.message }
      end

      result
    end

    private

    def attach_avatar(user)
      io = download(source_url_for(user))
      content_type = Marcel::MimeType.for(io, name: user.source_photo_path) || "application/octet-stream"
      io.rewind

      blob = ActiveStorage::Blob.find_by(key: storage_key_for(user)) || ActiveStorage::Blob.create_and_upload!(
        key: storage_key_for(user),
        io: io,
        filename: user.source_photo_path,
        content_type: content_type,
        identify: false,
        metadata: { "vista_id" => user.vista_id, "source_photo_path" => user.source_photo_path },
        service_name: ActiveStorage::Blob.service.name
      )

      user.avatar.attach(blob)
    end

    def avatar_available?(user)
      return false unless user.avatar.attached?

      user.avatar.blob.present? && ActiveStorage::Blob.service.exist?(user.avatar.blob.key)
    end

    def source_url_for(user)
      path = user.source_photo_path.to_s.strip
      return path if path.match?(%r{\Ahttps?://}i)

      URI.join(BASE_URL, path).to_s
    end

    def storage_key_for(user)
      [
        "vista",
        "agent_avatar",
        user.vista_id.presence || user.id,
        user.source_photo_path
      ].join("/")
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
