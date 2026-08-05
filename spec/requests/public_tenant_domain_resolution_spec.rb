require "rails_helper"

RSpec.describe "Public tenant domain resolution", type: :request do
  it "serve o site público com dados do tenant vinculado ao host" do
    default_tenant = Tenant.default
    conexao = Tenant.create!(name: "Conexão Imobiliária #{SecureRandom.hex(3)}", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")
    default_profile = default_tenant.profiles.find_by!(key: "agent")
    conexao_profile = conexao.profiles.find_by!(key: "agent")

    create(:admin_user, tenant: default_tenant, profile: default_profile, name: "Corretor Salute", active: true, display_on_site: true)
    create(:admin_user, tenant: conexao, profile: conexao_profile, name: "Corretor Conexão", active: true, display_on_site: true)
    hostname = "www.unitymob.com.br"
    TenantDomain.where(hostname: hostname).delete_all
    conexao.tenant_domains.create!(hostname: hostname, primary_domain: true)

    host! hostname
    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Corretor Conexão")
    expect(response.body).not_to include("Corretor Salute")
  end
end
