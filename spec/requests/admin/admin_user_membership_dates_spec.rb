require "rails_helper"

RSpec.describe "Datas de vínculo dos usuários", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "tenant_owner")) }
  let(:agent) { create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "agent"), vista_id: "DATA-10", source_created_on: "2018-03-20", source_departed_on: "2024-06-15", vista_payload: { "DATA" => "2018-03-20", "DATA_SAIDA" => "2024-06-15" }) }

  before do
    host! "localhost"
    ActionController::Base.allow_forgery_protection = false
    sign_in owner
  end

  it "exibe os dados do Vista no formulário e na ficha sem usar created_at" do
    get edit_admin_admin_user_path(agent)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[type="date"][name="admin_user[source_created_on]"]')["value"]).to eq("2018-03-20")
    expect(document.at_css('input[type="date"][name="admin_user[source_departed_on]"]')["value"]).to eq("2024-06-15")
    get admin_admin_user_path(agent)
    expect(response.body).to include("20/03/2018", "15/06/2024")
  end

  it "permite edição autorizada e preserva o payload bruto do Vista" do
    patch admin_admin_user_path(agent), params: { admin_user: { source_created_on: "2018-03-21", source_departed_on: "2024-06-16" } }
    expect(response).to have_http_status(:redirect)
    expect(agent.reload.source_created_on).to eq(Date.new(2018, 3, 21))
    expect(agent.source_departed_on).to eq(Date.new(2024, 6, 16))
    expect(agent.vista_payload["DATA"]).to eq("2018-03-20")
    expect(agent).to be_active
  end

  it "mantém as datas ao editar outro campo e permite limpar uma data explicitamente" do
    patch admin_admin_user_path(agent), params: { admin_user: { name: "Nome editado" } }
    expect(agent.reload.source_created_on).to eq(Date.new(2018, 3, 20))
    patch admin_admin_user_path(agent), params: { admin_user: { source_departed_on: "" } }
    expect(agent.reload.source_departed_on).to be_nil
    expect(agent.source_created_on).to eq(Date.new(2018, 3, 20))
  end

  it "rejeita datas invertidas sem salvar alteração parcial" do
    patch admin_admin_user_path(agent), params: { admin_user: { source_departed_on: "2017-01-01" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(agent.reload.source_departed_on).to eq(Date.new(2024, 6, 15))
  end

  it "oferece o mesmo cadastro em uma conta sem Vista" do
    other = Tenant.create!(name: "Conta sem Vista", slug: "sem-vista-datas-#{SecureRandom.hex(3)}")
    other_owner = create(:admin_user, tenant: other, profile: other.profiles.find_by!(key: "tenant_owner"))
    other_agent = create(:admin_user, tenant: other, profile: other.profiles.find_by!(key: "agent"), manager: other_owner)
    sign_out owner
    sign_in other_owner
    patch admin_admin_user_path(other_agent), params: { admin_user: { source_created_on: "2026-01-10", source_departed_on: "2026-10-20" } }
    expect(response).to have_http_status(:redirect)
    expect(other_agent.reload.source_created_on).to eq(Date.new(2026, 1, 10))
    expect(other_agent.source_departed_on).to eq(Date.new(2026, 10, 20))
    expect(other_agent.vista_id).to be_blank
  end

  it "não permite editar o histórico de outra conta" do
    other = Tenant.create!(name: "Outra datas", slug: "outra-datas-#{SecureRandom.hex(3)}")
    foreign = create(:admin_user, tenant: other, profile: other.profiles.find_by!(key: "agent"))
    patch admin_admin_user_path(foreign), params: { admin_user: { source_created_on: "2020-01-01" } }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.source_created_on).to be_nil
  end

  it "não permite edição sem permissão de gerenciar corretores" do
    sign_out owner
    sign_in agent
    patch admin_admin_user_path(agent), params: { admin_user: { source_created_on: "2020-01-01" } }
    expect(response).to have_http_status(:redirect)
    expect(agent.reload.source_created_on).to eq(Date.new(2018, 3, 20))
  end
end
