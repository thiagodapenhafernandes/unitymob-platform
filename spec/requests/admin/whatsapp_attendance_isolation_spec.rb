require "rails_helper"

# Uma conta nunca enxerga nem altera atendimentos, conversas ou automações de outra.
RSpec.describe "Isolamento entre contas no atendimento WhatsApp", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-iso-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}") }
  let(:other_owner) { create(:admin_user, :admin, tenant: other_tenant, email: "wa-iso-o-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_colleague) { create(:admin_user, tenant: other_tenant) }
  let(:other_conversation) { WhatsappConversation.create!(tenant: other_tenant, contact_phone: "5511988887777", contact_name: "Cliente Alheio") }
  let!(:other_attendance) do
    other_conversation.attendances.create!(tenant: other_tenant, admin_user: other_owner, button_text: "Assunto alheio", status: "open", opened_at: 1.hour.ago)
  end

  before do
    host! "localhost"
    sign_in admin
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
  end

  def request_ignoring_not_found
    yield
  rescue ActiveRecord::RecordNotFound
    nil
  end

  it "a gestao nao lista atendimentos de outra conta" do
    get admin_whatsapp_attendances_path

    expect(response.body).not_to include("Cliente Alheio")
    expect(response.body).not_to include("Assunto alheio")
  end

  it "nao transfere nem finaliza atendimento de outra conta, por nenhuma das telas" do
    request_ignoring_not_found { post transfer_admin_whatsapp_attendance_path(other_attendance), params: { to_admin_user_id: other_colleague.id } }
    request_ignoring_not_found { post finish_admin_whatsapp_attendance_path(other_attendance) }
    request_ignoring_not_found { post transfer_attendance_admin_whatsapp_conversation_path(other_conversation), params: { to_admin_user_id: other_colleague.id } }
    request_ignoring_not_found { post finish_attendance_admin_whatsapp_conversation_path(other_conversation) }

    expect(other_attendance.reload).to have_attributes(status: "open", admin_user_id: other_owner.id)
  end

  it "nao entrega contexto, anotacao nem conversa de outra conta" do
    request_ignoring_not_found { get context_admin_whatsapp_conversation_path(other_conversation) }
    expect(response).to have_http_status(:not_found)

    other_lead = other_tenant.leads.create!(name: "Lead alheio", phone: "5511988887777")
    other_conversation.update!(lead: other_lead)
    request_ignoring_not_found { post add_note_admin_whatsapp_conversation_path(other_conversation), params: { body: "invasao" } }
    expect(LeadActivity.where(lead_id: other_lead.id, kind: "note")).to be_empty
  end

  it "nao aceita automacao de outra conta em um botao do fluxo de resposta" do
    foreign_workflow = other_tenant.automation_workflows.create!(name: "Automação alheia")
    template = admin.tenant.whatsapp_templates.create!(
      name: "menu_iso", language: "pt_BR", category: "UTILITY", status: "APPROVED", usage_context: "response_flow", waba_id: "waba-iso",
      body: "Oi", buttons: [{ "kind" => "quick_reply", "text" => "Comprar" }]
    )

    post admin_whatsapp_response_flows_path, params: { whatsapp_response_flow: { name: "Iso", whatsapp_template_id: template.id, active: "1",
      button_actions: { "text:0:comprar" => { button_key: "text:0:comprar", button_text: "Comprar", action: "run_automation", automation_workflow_id: foreign_workflow.id.to_s } } } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(admin.tenant.whatsapp_response_flows.count).to eq(0)
  end

  it "a fila em tempo real so entrega a conversa a quem pode ve-la" do
    sent = []
    allow(InAppNotification).to receive(:broadcast_event!) { |user_id, payload| sent << [user_id, payload] }
    user = create(:admin_user, tenant: admin.tenant)

    Whatsapp::AttendanceManager.expire!(other_attendance)

    recipients = sent.map(&:first)
    expect(recipients).to include(other_owner.id)
    expect(recipients).not_to include(admin.id, user.id)
  end
end
