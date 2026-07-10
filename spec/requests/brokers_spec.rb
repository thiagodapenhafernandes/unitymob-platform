require "rails_helper"

RSpec.describe "Brokers", type: :request do
  before { host! "localhost" }

  it "exibe apenas corretores marcados para aparecer no site" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent")
    visible = create(:admin_user, name: "Corretor Visível", profile: broker_profile, active: true, display_on_site: true)
    hidden = create(:admin_user, name: "Corretor Oculto", profile: broker_profile, active: true, display_on_site: false)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible.name)
    expect(response.body).not_to include(hidden.name)
  end

  it "exibe perfis verticais customizados abaixo do Tenant Owner sem depender do nome do cargo" do
    tenant = Tenant.default
    custom_profile = tenant.profiles.create!(
      name: "Consultor Especialista",
      axis: "vertical",
      position: 700,
      active: true,
      permissions: Profile.default_permissions_for("Corretor")
    )
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    visible_custom = create(:admin_user, tenant: tenant, name: "Consultor Público", profile: custom_profile, active: true, display_on_site: true)
    visible_owner = create(:admin_user, tenant: tenant, name: "Owner Não Público", profile: owner_profile, role: :admin, active: true, display_on_site: true)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible_custom.name)
    expect(response.body).not_to include(visible_owner.name)
  end

  it "não exibe corretores de outro tenant no site público padrão" do
    default_tenant = Tenant.default
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    broker_profile = default_tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")

    visible = create(:admin_user, tenant: default_tenant, name: "Corretor Padrão", profile: broker_profile, active: true, display_on_site: true)
    other_visible = create(:admin_user, tenant: other_tenant, name: "Corretor Outro Tenant", profile: other_profile, active: true, display_on_site: true)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible.name)
    expect(response.body).not_to include(other_visible.name)
  end

  it "monta link de WhatsApp sem duplicar DDI quando telefone já está normalizado" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent")
    broker = create(
      :admin_user,
      name: "Corretor WhatsApp",
      profile: broker_profile,
      active: true,
      display_on_site: true,
      phone: "5547999729441"
    )

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(broker.name)
    expect(response.body).to include("https://wa.me/5547999729441")
    expect(response.body).not_to include("https://wa.me/555547999729441")
  end
end
