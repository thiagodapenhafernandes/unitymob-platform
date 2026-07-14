require "rails_helper"

RSpec.describe "Admin::Appointments", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "appt-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET /admin/appointments" do
    it "exibe a agenda da semana" do
      Appointment.create!(title: "Visita ap 302", admin_user: admin, starts_at: Time.current.change(hour: 10))

      get admin_appointments_path(team: "0")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Agenda", "ax-workspace-heading", "ax-dismissible-hint", "data-dismissible-key-value=\"agenda\"", "ax-appointment-grid", "ax-appointment-card", "Visita ap 302", "ax-modal-overlay")
      document = Nokogiri::HTML(response.body)
      view_links = document.css('a.ax-btn[href*="view="]')
      expect(view_links).not_to be_empty
      expect(view_links).to all(satisfy { |link| URI.parse(link["href"]).query.include?("team=0") })
      expect(document.at_css('a.ax-btn[aria-current="page"]')).to be_present
      expect(document.at_css('a.ax-btn--icon[aria-label="Período anterior"] i[aria-hidden="true"]')).to be_present
      expect(document.at_css('a.ax-btn--icon[aria-label="Próximo período"] i[aria-hidden="true"]')).to be_present
    end
  end

  describe "POST /admin/appointments" do
    it "agenda compromisso e registra na timeline do lead" do
      lead = create(:lead)

      expect {
        post admin_appointments_path, params: { appointment: { title: "Visita", kind: "visita", starts_at: 1.day.from_now, lead_id: lead.id } }
      }.to change(Appointment, :count).by(1)
       .and change { lead.activities.where(kind: "appointment_created").count }.by(1)

      expect(response).to have_http_status(:redirect)
    end

    it "não permite atribuir compromisso para usuário fora da subárvore do gestor" do
      tenant = Tenant.create!(name: "Tenant agenda #{SecureRandom.hex(3)}", slug: "tenant-agenda-#{SecureRandom.hex(3)}")
      owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
      manager_profile = Profile.create!(
        tenant: tenant,
        name: "Manager Agenda",
        axis: "vertical",
        position: 300,
        permissions: {
          "dashboard" => { "view" => true },
          "comercial" => { "view" => true, "manage" => true, "scope" => "team" }
        }
      )
      agent_profile = tenant.profiles.find_by!(key: "agent")
      owner = create(:admin_user, tenant: tenant, profile: owner_profile)
      manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner)
      peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner)
      sign_in manager

      post admin_appointments_path, params: {
        appointment: {
          title: "Visita fora da equipe",
          kind: "visita",
          starts_at: 1.day.from_now,
          admin_user_id: peer.id
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(Appointment.last.admin_user_id).to eq(manager.id)
      expect(Appointment.last.admin_user_id).not_to eq(peer.id)
    end
  end

  describe "PATCH /admin/appointments/:id" do
    it "marca como realizado e loga na timeline" do
      lead = create(:lead)
      appt = Appointment.create!(title: "Visita", admin_user: admin, lead: lead, starts_at: 1.hour.ago, status: "agendado")

      patch admin_appointment_path(appt), params: { appointment: { status: "realizado" } }

      expect(appt.reload.status).to eq("realizado")
      expect(lead.activities.where(kind: "appointment_done").count).to eq(1)
    end
  end
end
