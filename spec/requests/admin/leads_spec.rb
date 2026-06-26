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
      expect(response.body).to include("ax-leads-mobile-shell")
      expect(response.body).to include("ax-leads-mobile-filter-button")
      expect(response.body).to include("admin-push-banner")
      expect(response.body).to include("<details class=\"lead-filter-collapse\">")
      expect(response.body).not_to include("<details class=\"lead-filter-collapse\" open")
      expect(response.body).to include("Filtros do funil")
      expect(response.body.scan("<section class=\"ax-filter-form ax-leads-filters\">").size).to eq(1)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("details.lead-filter-collapse .ax-leads-filter-overlay")).to be_nil
      expect(document.at_css("details.lead-filter-collapse + .ax-leads-filter-overlay")).to be_present
      expect(response.body).to include("data-lead-url=\"#{admin_lead_path(Lead.find_by!(name: "Cliente Kanban"))}\"")
      expect(response.body).to include("Cliente Kanban")
      expect(response.body).to include("Em Atendimento")
      expect(response.body).not_to include("data-lead-kanban-drag-handle")
    end

    it "mantem a visualizacao em lista como alternativa" do
      create(:lead, name: "Cliente Lista", phone: "11999999999", status: "Novo")

      get admin_leads_path(view: "list")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lead-list-workspace")
      expect(response.body).to include("Total filtrado")
      expect(response.body).to include("WhatsApp")
      expect(response.body).not_to include("<table")
      expect(response.body).to include("Cliente Lista")
    end

    it "lembra a visualizacao escolhida pelo usuario entre sessoes" do
      create(:lead, name: "Cliente Memoria", phone: "11999999999", status: "Novo")

      get admin_leads_path(view: "list")
      expect(admin.reload.leads_view_mode).to eq("list")

      # Sem param e em nova sessao, volta na preferencia salva (nao no padrao).
      sign_out admin
      sign_in admin
      get admin_leads_path

      expect(response.body).to include("lead-list-workspace")
    end

    it "filtra por corretor, imóvel, contato e período" do
      broker = create(:admin_user, email: "broker-filter-#{SecureRandom.hex(8)}@salute.test")
      other_broker = create(:admin_user, email: "broker-filter-other-#{SecureRandom.hex(8)}@salute.test")
      property = create(:habitation, codigo: "lead-filter-#{SecureRandom.hex(6)}", titulo_anuncio: "Apartamento Filtro Lead")

      matching = create(:lead, name: "Lead Filtrado", phone: "11999999999", created_at: 1.day.ago, property_id: property.id)
      matching.update_columns(admin_user_id: broker.id, created_at: 1.day.ago, updated_at: 1.day.ago)

      other = create(:lead, name: "Lead Fora do Filtro", phone: "11888888888", email: "fora@example.com", created_at: 20.days.ago)
      other.update_columns(admin_user_id: other_broker.id, created_at: 20.days.ago, updated_at: 20.days.ago)

      get admin_leads_path(
        view: "list",
        broker_id: broker.id,
        property_q: property.codigo,
        property_filter: "with_property",
        contact_filter: "with_phone",
        start_date: 3.days.ago.to_date.iso8601,
        end_date: Date.current.iso8601
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Filtrado")
      expect(response.body).to include("Apartamento Filtro Lead")
      expect(response.body).to include("Corretor")
      expect(response.body).to include("Imóvel")
      expect(response.body).to include("Contato")
      expect(response.body).to include("Período")
      expect(response.body).not_to include("Lead Fora do Filtro")
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

    it "nao permite alterar origem pelo update administrativo" do
      lead = create(:lead, status: "Novo", origin: "webhook")

      patch admin_lead_path(lead),
            params: { lead: { origin: "manual", notes: "Contato conferido" } }

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(lead.reload.origin).to eq("webhook")
      expect(lead.notes).to eq("Contato conferido")
    end

    it "permite que o corretor atualize status do proprio lead via json" do
      broker_profile = Profile.create!(
        name: "Corretor Kanban #{SecureRandom.hex(4)}",
        permissions: Profile.default_permissions_for("Corretor")
      )
      broker = create(:admin_user, profile: broker_profile, email: "broker-kanban-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, status: "Aguardando Aceite")
      lead.update_columns(admin_user_id: broker.id, status: "Aguardando Aceite")

      sign_out admin
      sign_in broker

      patch admin_lead_path(lead),
            params: { lead: { status: "Em Atendimento" } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(lead.reload.status).to eq("Em Atendimento")
      expect(JSON.parse(response.body)).to include("status" => "Em Atendimento")
    end

    it "nao permite que corretor reatribua lead ou altere origem por parametro forjado" do
      broker_profile = Profile.create!(
        name: "Corretor bloqueio #{SecureRandom.hex(4)}",
        permissions: Profile.default_permissions_for("Corretor")
      )
      broker = create(:admin_user, profile: broker_profile, email: "broker-lock-#{SecureRandom.hex(4)}@salute.test")
      other_broker = create(:admin_user, profile: broker_profile, email: "broker-lock-other-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, status: "Aguardando Aceite", origin: "webhook")
      lead.update_columns(admin_user_id: broker.id, status: "Aguardando Aceite")

      sign_out admin
      sign_in broker

      patch admin_lead_path(lead),
            params: { lead: { status: "Em Atendimento", admin_user_id: other_broker.id, origin: "manual" } }

      expect(response).to redirect_to(admin_lead_path(lead))
      lead.reload
      expect(lead.status).to eq("Em Atendimento")
      expect(lead.admin_user_id).to eq(broker.id)
      expect(lead.origin).to eq("webhook")
    end

    it "retorna erro json claro quando o lead saiu da fila do corretor" do
      broker_profile = Profile.create!(
        name: "Corretor Kanban stale #{SecureRandom.hex(4)}",
        permissions: Profile.default_permissions_for("Corretor")
      )
      broker = create(:admin_user, profile: broker_profile, email: "broker-stale-#{SecureRandom.hex(4)}@salute.test")
      other_broker = create(:admin_user, profile: broker_profile, email: "broker-other-#{SecureRandom.hex(4)}@salute.test")
      lead = create(:lead, status: "Aguardando Aceite")
      lead.update_columns(admin_user_id: other_broker.id, status: "Aguardando Aceite")

      sign_out admin
      sign_in broker

      patch admin_lead_path(lead),
            params: { lead: { status: "Em Atendimento" } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:not_found)
      expect(response).not_to be_redirect
      expect(JSON.parse(response.body)).to include(
        "error" => "lead_unavailable",
        "message" => "Este lead saiu da sua fila ou expirou. Atualize o Kanban."
      )
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

    it "explica quando o lead nao possui imovel especifico atrelado" do
      lead = create(:lead, status: "Novo", property_id: nil)

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Imóvel de interesse")
      expect(response.body).to include("Lead sem imóvel específico")
      expect(response.body).to include("origem geral, campanha, webhook ou atendimento")
      expect(response.body).to include("Voltar")
      expect(response.body).not_to include("name=\"lead[origin]\"")
    end
  end

  describe "GET /admin/leads/:id/attend" do
    it "permite que o primeiro corretor reivindique um lead de Shark Tank" do
      broker_profile = Profile.create!(
        name: "Corretor Shark #{SecureRandom.hex(4)}",
        permissions: Profile.default_permissions_for("Corretor")
      )
      broker = create(:admin_user, :field_agent, profile: broker_profile, email: "broker-shark-#{SecureRandom.hex(4)}@salute.test")
      rule = create(:distribution_rule, distribution_mode: :shark_tank)
      rule_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker)
      PushSetting.instance.update!(lead_click_action: "system")
      Lead.skip_callback(:commit, :after, :route_lead)
      lead = create(:lead, status: :waiting_acceptance, admin_user: nil, distribution_rule: rule)

      sign_out admin
      sign_in broker

      get attend_admin_lead_path(lead)

      expect(response).to redirect_to(admin_lead_path(lead))
      lead.reload
      expect(lead.admin_user_id).to eq(broker.id)
      expect(lead.status).to eq(Lead.status_value(:em_atendimento))
      expect(rule_agent.reload.last_lead_received_at).to be_present
      expect(lead.activities.where(kind: "accepted").last.metadata).to include("shark_tank" => true)
    ensure
      Lead.set_callback(:commit, :after, :route_lead)
    end

    it "mostra lead ja atendido para corretor que perdeu a corrida do Shark Tank" do
      broker_profile = Profile.create!(
        name: "Corretor Shark Lost #{SecureRandom.hex(4)}",
        permissions: Profile.default_permissions_for("Corretor")
      )
      winner = create(:admin_user, :field_agent, profile: broker_profile, email: "broker-winner-#{SecureRandom.hex(4)}@salute.test")
      loser = create(:admin_user, :field_agent, profile: broker_profile, email: "broker-loser-#{SecureRandom.hex(4)}@salute.test")
      Lead.skip_callback(:commit, :after, :route_lead)
      lead = create(:lead, status: :waiting_acceptance, admin_user: winner)

      sign_out admin
      sign_in loser

      get attend_admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead já atendido")
      expect(lead.reload.admin_user_id).to eq(winner.id)
    ensure
      Lead.set_callback(:commit, :after, :route_lead)
    end
  end
end
