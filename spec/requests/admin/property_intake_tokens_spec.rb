require "rails_helper"

RSpec.describe "Gestão do token da API de captação", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:path) { admin_property_intake_token_path }

  before { host! "localhost" }

  def issued_token
    Nokogiri::HTML(response.body).at_css("#issued_property_intake_token")&.[]("value")
  end

  def token_version
    Nokogiri::HTML(response.body).at_css("input[name=token_version]").[]("value")
  end

  def intake_status(token)
    post "/api/v1/property_intakes", params: {}, as: :json, headers: { "Authorization" => "Bearer #{token}" }
    response.status
  end

  it "emite, rotaciona e revoga apenas o token da conta autenticada" do
    other = Tenant.create!(name: "Outra conta", slug: "outro-token-api", property_intake_token_digest: "outro-digest")
    sign_in admin

    post path, params: { tenant_id: other.id }
    expect(response).to have_http_status(:ok)
    expect(response.headers.fetch("Cache-Control")).to include("no-store")
    original = issued_token
    expect(original).to match(/\A[a-f0-9]{64}\z/)
    expect(admin.tenant.reload.property_intake_token_digest).to eq(Digest::SHA256.hexdigest(original))
    expect(intake_status(original)).to eq(422)

    get path
    expect(response.body).not_to include(original)
    expect(issued_token).to be_nil
    original_version = token_version

    post path
    expect(response).to have_http_status(:see_other)
    expect(admin.tenant.reload.property_intake_token_digest).to eq(Digest::SHA256.hexdigest(original))

    patch path, params: { token_version: original_version }
    replacement = issued_token
    replacement_version = token_version
    expect(replacement).to match(/\A[a-f0-9]{64}\z/)
    expect(replacement).not_to eq(original)
    expect(intake_status(original)).to eq(401)
    expect(intake_status(replacement)).to eq(422)

    patch path, params: { token_version: original_version }
    expect(response).to have_http_status(:see_other)
    expect(intake_status(replacement)).to eq(422)

    delete path, params: { token_version: replacement_version }
    expect(response).to have_http_status(:see_other)
    expect(intake_status(replacement)).to eq(401)
    expect(admin.tenant.reload.property_intake_token_digest).to be_nil
    expect(other.reload.property_intake_token_digest).to eq("outro-digest")
  end

  it "bloqueia a tela e todas as mutações para usuário operacional" do
    profile = Profile.create!(tenant: admin.tenant, name: "Operador de integrações", axis: "vertical",
                              permissions: { "integracoes" => { "manage" => true } })
    broker = create(:admin_user, tenant: admin.tenant, profile: profile)
    expect(broker.can?(:manage, :integracoes)).to be(true)
    sign_in broker

    %i[get post patch delete].each do |verb|
      public_send(verb, path)
      expect(response).to redirect_to(admin_root_path)
    end

    expect(admin.tenant.reload.property_intake_token_digest).to be_nil
  end
end
