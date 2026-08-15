require "active_storage/service/s3_service"

module ActiveStorage
  class Service::DigitalOceanSpacesService < Service::S3Service
    def url_for_direct_upload(key, expires_in:, content_type:, content_length:, checksum:, custom_metadata: {})
      instrument :url, key: key do |payload|
        generated_url = object_for(key).presigned_url :put,
          expires_in: expires_in.to_i,
          content_type: content_type,
          content_length: content_length,
          metadata: custom_metadata,
          whitelist_headers: ["content-length"],
          **upload_options

        payload[:url] = generated_url
        generated_url
      end
    end

    def headers_for_direct_upload(key, content_type:, checksum:, filename: nil, disposition: nil, custom_metadata: {}, **)
      content_disposition = content_disposition_with(type: disposition, filename: filename) if filename

      { "Content-Type" => content_type, "Content-Disposition" => content_disposition, **custom_metadata_headers(custom_metadata) }.compact
    end

    private

    def upload_with_single_part(key, io, checksum: nil, content_type: nil, content_disposition: nil, custom_metadata: {})
      object_for(key).put(body: io, content_type: content_type, content_disposition: content_disposition, metadata: custom_metadata, **upload_options)
    rescue Aws::S3::Errors::BadDigest
      raise ActiveStorage::IntegrityError
    end
  end
end
