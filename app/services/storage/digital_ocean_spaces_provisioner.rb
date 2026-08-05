require "aws-sdk-s3"

module Storage
  class DigitalOceanSpacesProvisioner
    Result = Struct.new(:ok?, :message, :created, :configured, keyword_init: true)

    def initialize(setting:)
      @setting = setting
    end

    def call
      return missing_configuration unless setting.digital_ocean_ready?

      created = ensure_bucket!
      configure_cors!
      test_upload!

      Result.new(
        ok?: true,
        created: created,
        configured: true,
        message: success_message(created)
      )
    rescue Aws::S3::Errors::BucketAlreadyExists
      Result.new(ok?: false, created: false, configured: false, message: "O bucket #{bucket} já existe em outra conta ou não está acessível por esta chave.")
    rescue Aws::S3::Errors::ServiceError => e
      Result.new(ok?: false, created: false, configured: false, message: "DigitalOcean Spaces recusou a configuração: #{e.class.name.demodulize} - #{e.message}")
    rescue StandardError => e
      Result.new(ok?: false, created: false, configured: false, message: "Falha ao provisionar bucket DigitalOcean: #{e.class} - #{e.message}")
    end

    private

    attr_reader :setting

    def ensure_bucket!
      client.head_bucket(bucket: bucket)
      false
    rescue Aws::S3::Errors::ServiceError => e
      raise unless missing_bucket_error?(e)

      client.create_bucket(bucket: bucket)
      true
    end

    def configure_cors!
      client.put_bucket_cors(
        bucket: bucket,
        cors_configuration: {
          cors_rules: [
            {
              allowed_methods: %w[GET HEAD PUT POST],
              allowed_origins: ["*"],
              allowed_headers: ["*"],
              expose_headers: ["ETag"],
              max_age_seconds: 3600
            }
          ]
        }
      )
    end

    def test_upload!
      key = "diagnostics/storage-provision-#{SecureRandom.hex(8)}.txt"
      client.put_object(
        bucket: bucket,
        key: key,
        body: "unitymob storage provision #{Time.current.to_i}",
        content_type: "text/plain"
      )
      client.delete_object(bucket: bucket, key: key)
    end

    def client
      @client ||= Aws::S3::Client.new(
        access_key_id: setting.do_spaces_access_key_id,
        secret_access_key: setting.do_spaces_secret_access_key,
        region: setting.do_spaces_region,
        endpoint: setting.do_spaces_endpoint,
        force_path_style: false
      )
    end

    def bucket
      setting.do_spaces_bucket
    end

    def public_base_url
      setting.do_spaces_public_base_url.presence || setting.digital_ocean_origin_base_url
    end

    def success_message(created)
      action = created ? "criado" : "validado"
      "Bucket #{bucket} #{action} no DigitalOcean Spaces. CORS aplicado, upload/remoção testados e base pública sem CDN: #{public_base_url}."
    end

    def missing_configuration
      Result.new(
        ok?: false,
        created: false,
        configured: false,
        message: "Configuração DigitalOcean incompleta. Informe bucket, região, endpoint, Access Key e Secret Key."
      )
    end

    def missing_bucket_error?(error)
      %w[NotFound NoSuchBucket].include?(error.class.name.demodulize)
    end
  end
end
