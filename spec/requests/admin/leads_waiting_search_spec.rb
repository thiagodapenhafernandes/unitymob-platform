require "rails_helper"

RSpec.describe "Busca de leads aguardando aceite", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let!(:waiting) { create(:lead, tenant: admin.tenant, admin_user: admin, name: "Grazielle Busca Aceite", email: "grazielle.busca@example.test", phone: "5547991629509", status: "Aguardando Aceite") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "encontra por nome, telefone ou email sem selecionar status na lista e Kanban" do
    %w[list kanban].each do |view|
      ["Grazielle", "47991629509", waiting.email].each do |query|
        get admin_leads_path, params: { view: view, q: query }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(waiting.name), "view=#{view} query=#{query} stored_phone=#{waiting.reload.phone}"
      end
    end
  end

  it "mantém a exclusão sem busca e respeita outro status selecionado" do
    get admin_leads_path, params: { view: "list" }
    expect(response.body).not_to include(waiting.name)
    get admin_leads_path, params: { view: "list", q: "Grazielle", status: "Em Atendimento" }
    expect(response.body).not_to include(waiting.name)
    get admin_leads_path, params: { view: "list", status: "Aguardando Aceite" }
    expect(response.body).to include(waiting.name)
  end

  it "respeita o responsável selecionado mesmo pesquisando" do
    other = create(:admin_user, :admin, tenant: admin.tenant)
    get admin_leads_path, params: { view: "list", q: "Grazielle", broker_id: other.id }
    expect(response.body).not_to include(waiting.name)
  end
end
