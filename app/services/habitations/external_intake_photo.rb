require "net/http"
require "tempfile"
require "timeout"

module Habitations
  class ExternalIntakePhoto
    MAX_BYTES = 8.megabytes
    EXTENSIONS = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze

    def self.download(url)
      policy = Automation::WebhookUrlPolicy
      uri = policy.parse(url)
      unless uri.is_a?(URI::HTTPS) && uri.hostname.present? && uri.port == 443 && uri.userinfo.nil?
        raise ExternalIntake::Invalid, "URL de foto inválida"
      end

      file = Tempfile.new("property-intake-photo", binmode: true)
      Timeout.timeout(10) do
        addresses = policy.resolve(uri.hostname)
        if addresses.empty? || addresses.any? { |ip| policy.blocked_ip?(ip) }
          raise ExternalIntake::Invalid, "Destino de foto inválido"
        end

        http = Net::HTTP.new(uri.hostname, uri.port, nil)
        http.ipaddr = addresses.first.to_s
        http.use_ssl = true
        http.open_timeout = 3
        http.read_timeout = 3
        http.max_retries = 0
        http.request(Net::HTTP::Get.new(uri.request_uri, "Accept-Encoding" => "identity")) do |response|
          unless response.is_a?(Net::HTTPOK)
            raise ExternalIntake::Invalid, "Foto indisponível"
          end

          response.read_body do |chunk|
            raise ExternalIntake::Invalid, "Foto excede 8 MB" if file.size + chunk.bytesize > MAX_BYTES

            file.write(chunk)
          end
        end
      end

      file.rewind
      type = Marcel::MimeType.for(file)
      extension = EXTENSIONS[type]
      raise ExternalIntake::Invalid, "Envie fotos JPEG, PNG ou WebP" unless extension

      file.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "foto.#{extension}", type: type)
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      raise ExternalIntake::Invalid, "Foto indisponível"
    ensure
      file&.close! unless upload
    end
  end
end
