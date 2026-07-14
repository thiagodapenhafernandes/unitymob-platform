require "rails_helper"

RSpec.describe "Admin::SeoRedirects", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "seo-redirects-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outro site #{SecureRandom.hex(3)}", slug: "outro-site-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista apenas redirecionamentos do tenant atual" do
    current_path = "/origem-local-#{SecureRandom.hex(4)}"
    other_path = "/origem-externa-#{SecureRandom.hex(4)}"
    admin.tenant.seo_redirects.create!(from_path: current_path, to_path: "/destino-local", status_code: 301, active: true)
    other_tenant.seo_redirects.create!(from_path: other_path, to_path: "/destino-externo", status_code: 302, active: true)

    get admin_seo_redirects_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_path, "seo_redirect_from_path", "seo_redirect_to_path", "seo_redirect_status_code")
    expect(response.body).not_to include(other_path)
  end
end
