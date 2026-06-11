require "rails_helper"

RSpec.describe "Admin::Leads", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "leads-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET /admin/leads" do
    it "exibe o kanban como visualizacao padrao" do
      create(:lead, name: "Cliente Kanban", phone: "11999999999", status: "Novo")
      create(:lead, name: "Cliente Atendimento", phone: "11888888888", status: "Em Atendimento")

      get admin_leads_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lead-kanban")
      expect(response.body).to include("Cliente Kanban")
      expect(response.body).to include("Em Atendimento")
    end

    it "mantem a visualizacao em lista como alternativa" do
      create(:lead, name: "Cliente Lista", phone: "11999999999", status: "Novo")

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<table")
      expect(response.body).to include("Cliente Lista")
    end
  end

  describe "PATCH /admin/leads/:id" do
    it "atualiza status dinamico via json" do
      lead = create(:lead, status: "Novo")

      expect {
        patch admin_lead_path(lead),
              params: { lead: { status: "Em Atendimento" } },
              headers: { "ACCEPT" => "application/json" }
      }.to change(LeadAuditLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(lead.reload.status).to eq("Em Atendimento")
      expect(JSON.parse(response.body)).to include("status" => "Em Atendimento")

      log = LeadAuditLog.last
      expect(log).to have_attributes(lead_id: lead.id, admin_user_id: admin.id, action: "status_changed", source: "admin")
      expect(log.changed_fields).to include("status")
    end

    it "exibe histórico de alterações no detalhe do lead" do
      lead = create(:lead, status: "Novo")
      create(:lead_audit_log, lead: lead, admin_user: admin, action: "status_changed")

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Histórico")
      expect(response.body).to include("Histórico do Lead")
      expect(response.body).to include("alterou o status do lead")
    end
  end
end
