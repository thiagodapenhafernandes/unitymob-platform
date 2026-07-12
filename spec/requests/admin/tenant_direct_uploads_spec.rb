require "rails_helper"

RSpec.describe "Tenant direct uploads", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:blob_params) do
    {
      blob: {
        filename: "foto.jpg",
        byte_size: 4,
        checksum: Digest::MD5.base64digest("test"),
        content_type: "image/jpeg"
      }
    }
  end

  before { host! "localhost" }

  it "records the authenticated tenant in blob metadata" do
    admin = create(:admin_user, :admin)
    sign_in admin

    post rails_direct_uploads_path, params: blob_params, as: :json

    expect(response).to have_http_status(:ok)
    expect(ActiveStorage::Blob.order(:id).last.metadata["tenant_id"]).to eq(admin.tenant_id)
  end

  it "rejects direct uploads without a tenant context" do
    sign_in create(:admin_user, super_admin: true)

    expect { post rails_direct_uploads_path, params: blob_params, as: :json }.not_to change(ActiveStorage::Blob, :count)
    expect(response).to have_http_status(:forbidden)
  end
end
