require "rails_helper"

RSpec.describe "Admin session recovery", type: :request do
  include Devise::Test::IntegrationHelpers

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "redireciona para login quando a sessao admin tem token CSRF invalido" do
    admin = create(:admin_user, :admin)
    lead = create(:lead, tenant: admin.tenant)

    host! "localhost"
    sign_in admin

    patch admin_lead_path(lead), params: { lead: { name: "Lead atualizado" } }, headers: { "X-CSRF-Token" => "invalid-token" }

    expect(response).to redirect_to(new_admin_user_session_path)
    follow_redirect!
    expect(response.body).to include("Sua sessão expirou")
  end
end
