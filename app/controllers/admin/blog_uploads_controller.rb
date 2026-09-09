require "aws-sdk-s3"

class Admin::BlogUploadsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }

  def create
    file = params.require(:file)
    return render json: { error: "Arquivo inválido." }, status: :unprocessable_entity unless file.is_a?(ActionDispatch::Http::UploadedFile)

    blob = Blog::Storage.upload!(file, tenant: current_tenant)
    render json: { sgid: blob.attachable_sgid, url: rails_blob_path(blob, only_path: true), signed_id: blob.signed_id, filename: blob.filename.to_s, content_type: blob.content_type, filesize: blob.byte_size }, status: :created
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError
    render json: { error: "Não foi possível enviar ao Spaces. Tente novamente." }, status: :service_unavailable
  end
end
