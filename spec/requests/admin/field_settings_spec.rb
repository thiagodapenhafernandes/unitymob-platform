require "rails_helper"

RSpec.describe "Admin::FieldSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "field-settings-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outra equipe #{SecureRandom.hex(3)}", slug: "outra-equipe-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  after { Current.reset }

  it "renderiza a configuração com usuários ativos apenas do tenant atual" do
    current_user = create(:admin_user, tenant: admin.tenant, name: "Corretor local #{SecureRandom.hex(4)}")
    other_user = create(:admin_user, tenant: other_tenant, name: "Corretor externo #{SecureRandom.hex(4)}")

    get edit_admin_field_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_user.name, "field_enabled", "Bloqueios pontuais de check-in", 'role="switch"')
    expect(response.body).not_to include(other_user.name)
    expect(response.body).to include(block_agent_admin_field_settings_path, admin_stores_path)
    expect(response.body).to include("Resumo da operação de campo", "Usuários ativos", "Lojas ativas", "Bloqueios")
    expect(response.body).to include("Acesso dos usuários ativos da conta ao check-in geolocalizado")
    expect(response.body).to include("Bloquear check-in para #{current_user.name}")
  end

  it "le e grava a ativacao no tenant atual sem alterar outra conta" do
    Setting.set(FieldFeatureGate::SETTING_KEY, "true", tenant: admin.tenant)
    Setting.set(FieldFeatureGate::SETTING_KEY, "true", tenant: other_tenant)

    patch admin_field_settings_path, params: { enabled: "0" }

    expect(response).to redirect_to(edit_admin_field_settings_path)
    expect(Setting.get(FieldFeatureGate::SETTING_KEY, "false", tenant: admin.tenant)).to eq("false")
    expect(Setting.get(FieldFeatureGate::SETTING_KEY, "false", tenant: other_tenant)).to eq("true")
  end

  it "nao altera o bloqueio de usuario pertencente a outro tenant" do
    other_user = create(:admin_user, tenant: other_tenant)

    patch block_agent_admin_field_settings_path, params: { admin_user_id: other_user.id }

    expect(response).to have_http_status(:not_found)
    expect(FieldFeatureGate.disabled_agent_ids(tenant: admin.tenant)).not_to include(other_user.id)
    expect(FieldFeatureGate.disabled_agent_ids(tenant: other_tenant)).not_to include(other_user.id)
  end
end
