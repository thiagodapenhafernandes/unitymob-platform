require "rails_helper"

RSpec.describe "Gestão de atendimentos WhatsApp", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-mgmt-#{SecureRandom.hex(6)}@salute.test") }
  let(:colleague) { create(:admin_user, tenant: admin.tenant) }
  let(:rule) { create(:distribution_rule, tenant: admin.tenant) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  let(:conversation) { WhatsappConversation.create!(tenant: admin.tenant, contact_phone: "5547999990055", contact_name: "Cliente Gestão", lead: lead, assigned_admin_user: admin) }
  let!(:attendance) do
    create(:distribution_rule_agent, tenant: admin.tenant, distribution_rule: rule, admin_user: colleague, position: 1)
    conversation.attendances.create!(tenant: admin.tenant, admin_user: admin, lead: lead, distribution_rule: rule, agent_ids: [colleague.id],
                                     button_key: "text:0:comprar", button_text: "Comprar ou Investir", status: "open", opened_at: 2.hours.ago)
  end

  before do
    host! "localhost"
    sign_in admin
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
  end

  it "lista os atendimentos em curso com dono, assunto e acoes" do
    get admin_whatsapp_attendances_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Gestão de atendimentos").and include("Cliente Gestão").and include("Comprar ou Investir").and include(admin.name)
    expect(response.body).to include(transfer_admin_whatsapp_attendance_path(attendance)).and include(finish_admin_whatsapp_attendance_path(attendance))
  end

  it "transfere pelo painel de gestao" do
    post transfer_admin_whatsapp_attendance_path(attendance), params: { to_admin_user_id: colleague.id }

    expect(attendance.reload.admin_user).to eq(colleague)
    expect(flash[:notice]).to include(colleague.name)
  end

  it "recusa transferir para quem nao e candidato" do
    outsider = create(:admin_user, tenant: admin.tenant)

    post transfer_admin_whatsapp_attendance_path(attendance), params: { to_admin_user_id: outsider.id }

    expect(attendance.reload.admin_user).to eq(admin)
    expect(flash[:alert]).to include("colega válido")
  end

  it "finaliza pelo painel de gestao" do
    allow(Whatsapp::ServiceWindowGuard).to receive(:call).and_return(double(locked?: true))

    post finish_admin_whatsapp_attendance_path(attendance)

    expect(attendance.reload).to have_attributes(status: "closed", closed_by_id: admin.id)
  end

  it "mostra os encerrados dos ultimos 7 dias com o motivo" do
    attendance.update!(status: "closed", closed_at: 1.day.ago, close_reason: "window_expired")

    get admin_whatsapp_attendances_path(status: "closed")

    expect(response.body).to include("janela de 24h do WhatsApp fechou")
  end

  it "usuario de escopo proprio so ve os atendimentos das proprias conversas" do
    sign_out admin
    profile = admin.tenant.profiles.create!(name: "Atendente WhatsApp", axis: "vertical", position: 300,
                                            permissions: { "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" } })
    agent = create(:admin_user, tenant: admin.tenant, profile: profile)
    sign_in agent

    get admin_whatsapp_attendances_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Cliente Gestão")
  end

  it "o painel da conversa oferece a transferencia e o endpoint de contexto responde" do
    get admin_whatsapp_conversation_path(conversation)
    expect(response.body).to include(transfer_attendance_admin_whatsapp_conversation_path(conversation))

    get context_admin_whatsapp_conversation_path(conversation)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Atendimento em curso")

    post transfer_attendance_admin_whatsapp_conversation_path(conversation), params: { to_admin_user_id: colleague.id }
    expect(attendance.reload.admin_user).to eq(colleague)
  end
end
