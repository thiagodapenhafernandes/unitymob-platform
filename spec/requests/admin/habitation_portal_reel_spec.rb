require "rails_helper"

RSpec.describe "Admin habitation portal reel", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:habitation) { create(:habitation, tenant: admin.tenant, videos: ["https://youtu.be/oldvideo"]) }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  it "offers a shared upload field without changing the existing video inputs" do
    get admin_habitation_media_path(habitation)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('input[name="habitation[portal_reel]"]')["accept"]).to include(".mp4", ".mov")
    expect(doc.at_css('input[name="habitation[videos][]"]')["value"]).to eq("https://youtu.be/oldvideo")
  end

  it "uploads and replaces just the reel, preserving pictures and video links" do
    original_pictures = habitation.pictures
    2.times do
      patch admin_habitation_media_path(habitation), params: {
        habitation: { portal_reel: fixture_file_upload("portal_reel.mp4", "video/mp4") }
      }
      expect(response).to have_http_status(:redirect)
    end
    habitation.reload
    expect(habitation.portal_reel).to be_attached
    expect(habitation.pictures).to eq(original_pictures)
    expect(habitation.videos).to eq(["https://youtu.be/oldvideo"])
    expect(habitation.portal_reel_attachment.blob.filename.to_s).to eq("portal_reel.mp4")
    expect(habitation.habitation_audit_logs.last.changeset).to have_key("portal_reel_attachments")
  end

  it "rejects links and signed blob IDs instead of attaching another account's blob" do
    ["https://youtube.com/shorts/example", "someone-elses-signed-blob-id"].each do |value|
      sign_in admin
      patch admin_habitation_media_path(habitation), params: { habitation: { portal_reel: value } }
      expect(response).to have_http_status(:bad_request), response.headers["Location"]
    end
    expect(habitation.reload.portal_reel).not_to be_attached
  end

  it "does not allow uploading a reel to another tenant's property" do
    other = create(:habitation, tenant: Tenant.create!(name: "Outra conta", slug: "reel-admin-other"))
    patch admin_habitation_media_path(other), params: {
      habitation: { portal_reel: fixture_file_upload("portal_reel.mp4", "video/mp4") }
    }
    expect(response).to have_http_status(:not_found)
    expect(other.reload.portal_reel).not_to be_attached
  end
  it "honors a profile that locks reels in both the form and the update" do
    editor = create(:admin_user)
    permissions = Profile.default_permissions_for("Corretor").deep_dup
    permissions["imoveis"]["locked_fields"] = ["portal_reel"]
    editor.profile.update!(permissions: permissions)
    habitation.update!(admin_user: editor)
    sign_in editor
    get admin_habitation_media_path(habitation)
    expect(response).to have_http_status(:ok)
    input = Nokogiri::HTML(response.body).at_css('input[name="habitation[portal_reel]"]')
    expect(input["disabled"]).to be_present
    patch admin_habitation_media_path(habitation), params: {
      habitation: { portal_reel: fixture_file_upload("portal_reel.mp4", "video/mp4") }
    }
    expect(response).to have_http_status(:redirect)
    expect(habitation.reload.portal_reel).not_to be_attached
  end

  it "preserves a saved reel when the upload input is empty" do
    patch admin_habitation_media_path(habitation), params: {
      habitation: { portal_reel: fixture_file_upload("portal_reel.mp4", "video/mp4") }
    }
    blob_id = habitation.reload.portal_reel.blob.id
    patch admin_habitation_media_path(habitation), params: { habitation: { portal_reel: "", podcast_url: "https://example.test/podcast" } }
    expect(response).to have_http_status(:redirect)
    expect(habitation.reload.portal_reel.blob.id).to eq(blob_id)
    expect(habitation.podcast_url).to eq("https://example.test/podcast")
  end

end
