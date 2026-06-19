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

      get admin_appointments_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Agenda")
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
