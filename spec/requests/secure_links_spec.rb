require "rails_helper"

RSpec.describe "SecureLinks", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:corretor) { create(:admin_user, :field_agent, name: "Corretor Seguro") }
  let(:outro_corretor) { create(:admin_user, :field_agent, name: "Corretor Ganhador") }

  before do
    Lead.skip_callback(:commit, :after, :route_lead)
    host! "localhost"
  end

  after do
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "mostra o card seguro de detalhes quando o push abre com details=1 mesmo logado" do
    lead = create(:lead, name: "Cliente Detalhe", phone: "11999999999", status: :waiting_acceptance, admin_user: corretor)
    link = SecureLink.link_for(lead, :attend, expiry_days: 7, issued_to: corretor)
    sign_in admin

    get secure_link_path(link.token), params: { details: "1" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lead recebido")
    expect(response.body).to include("Cliente Detalhe")
    expect(response.body).to include("Abrir WhatsApp do lead")
    expect(lead.reload.status).to eq(Lead.status_value(:em_atendimento))
  end

  it "marca como atendido ao clicar no WhatsApp do card seguro de detalhes" do
    lead = create(:lead, name: "Cliente WhatsApp", phone: "11999999999", status: :waiting_acceptance, admin_user: corretor)
    link = SecureLink.link_for(lead, :view, expiry_days: 7, issued_to: corretor)

    get secure_link_path(link.token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(secure_link_path(link.token, contact: "whatsapp"))
    expect(lead.reload.status).to eq(Lead.status_value(:waiting_acceptance))

    get secure_link_path(link.token), params: { contact: "whatsapp" }

    expect(response).to redirect_to(lead.direct_whatsapp_url)
    expect(lead.reload.status).to eq(Lead.status_value(:em_atendimento))
    expect(lead.activities.where(kind: "accepted").last.metadata).to include(
      "via" => "whatsapp",
      "secure_link" => true
    )
  end

  it "marca como atendido ao clicar no e-mail do card seguro de detalhes" do
    lead = create(:lead, name: "Cliente E-mail", phone: "11999999999", email: "cliente@example.com", status: :waiting_acceptance, admin_user: corretor)
    link = SecureLink.link_for(lead, :view, expiry_days: 7, issued_to: corretor)

    get secure_link_path(link.token), params: { contact: "email" }

    expect(response).to redirect_to("mailto:cliente@example.com")
    expect(lead.reload.status).to eq(Lead.status_value(:em_atendimento))
    expect(lead.activities.where(kind: "accepted").last.metadata).to include(
      "via" => "email",
      "secure_link" => true
    )
  end

  it "nao abre dados nem aceita link antigo quando o lead ja pertence a outro corretor" do
    lead = create(:lead, name: "Cliente Disputa", phone: "11999999999", status: :waiting_acceptance, admin_user: outro_corretor)
    link = SecureLink.link_for(lead, :attend, expiry_days: 7, issued_to: corretor)

    get secure_link_path(link.token), params: { details: "1" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lead já atendido")
    expect(response.body).not_to include("11999999999")
    expect(lead.reload.status).to eq(Lead.status_value(:waiting_acceptance))
    expect(lead.activities.where(kind: "accepted")).to be_empty
  end

  it "recusa ack em background de notificacao antiga quando o lead ja pertence a outro corretor" do
    lead = create(:lead, name: "Cliente Ack Antigo", phone: "11999999999", status: :waiting_acceptance, admin_user: outro_corretor)
    link = SecureLink.link_for(lead, :attend, expiry_days: 7, issued_to: corretor)

    get secure_link_path(link.token), params: { ack: "1" }

    expect(response).to have_http_status(:conflict)
    expect(lead.reload.status).to eq(Lead.status_value(:waiting_acceptance))
    expect(lead.activities.where(kind: "accepted")).to be_empty
  end

  it "mostra lead ja atendido quando perde a corrida do Shark Tank durante o claim" do
    lead = create(:lead, name: "Cliente Corrida", phone: "11999999999", status: :waiting_acceptance, admin_user: nil)
    link = SecureLink.link_for(lead, :attend, expiry_days: 7, issued_to: corretor)
    allow(Lead).to receive(:claim!).with(lead.id, corretor.id).and_wrap_original do
      lead.update!(admin_user: outro_corretor, status: Lead.status_value(:em_atendimento))
      false
    end

    get secure_link_path(link.token), params: { details: "1" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lead já atendido")
    expect(response.body).not_to include("11999999999")
    expect(lead.reload.admin_user_id).to eq(outro_corretor.id)
    expect(lead.activities.where(kind: "accepted")).to be_empty
  end
end
