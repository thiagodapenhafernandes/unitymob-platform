require "rails_helper"

RSpec.describe "Atendimento WhatsApp em curso", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-att-#{SecureRandom.hex(6)}@salute.test") }
  let(:conversation) { WhatsappConversation.create!(tenant: admin.tenant, contact_phone: "5547999990077", contact_name: "Bia") }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  let!(:attendance) do
    conversation.attendances.create!(tenant: admin.tenant, admin_user: admin, lead: lead, button_key: "text:0:comprar", button_text: "Comprar ou Investir",
                                     status: "open", opened_at: Time.current, finish_message: "Até logo!")
  end

  before do
    host! "localhost"
    sign_in admin
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
    allow(Whatsapp::ThreadBroadcaster).to receive(:queue_refreshed)
  end

  it "mostra o atendimento e o botao Finalizar na conversa, e marca o aceite do dono" do
    get admin_whatsapp_conversation_path(conversation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Atendimento em curso")
    expect(response.body).to include("Finalizar atendimento")
    expect(attendance.reload).to be_accepted
  end

  it "mostra assunto e dono na lista, quem enviou cada mensagem e o ultimo atendimento finalizado" do
    conversation.messages.create!(direction: "outbound", msg_type: "text", body: "Olá!", status: "sent", admin_user: admin)

    get admin_whatsapp_conversation_path(conversation)
    expect(response.body).to include("wa-inbox-conversation__attendance").and include("Comprar ou Investir")
    expect(response.body).to include("wa-inbox-bubble__author").and include(admin.name)

    attendance.update!(status: "closed", closed_at: Time.current, close_reason: "finished", closed_by: admin)
    get admin_whatsapp_conversation_path(conversation)
    expect(response.body).to include("Último atendimento").and include("Finalizado por #{admin.name}")
  end

  it "nao zera o nao lida do atendente quando outra pessoa apenas visualiza" do
    other_owner = create(:admin_user, tenant: admin.tenant)
    attendance.update!(admin_user: other_owner)
    conversation.update_columns(unread_count: 3)

    get admin_whatsapp_conversation_path(conversation)

    expect(conversation.reload.unread_count).to eq(3)
  end

  it "marca como lidas as notificacoes da conversa ao abri-la e avisa o sino" do
    mine = InAppNotification.notify!(admin_user: admin, kind: "whatsapp_attendance", title: "Novo atendimento", metadata: { conversation_id: conversation.id })
    other = InAppNotification.notify!(admin_user: admin, kind: "whatsapp_attendance", title: "Outro", metadata: { conversation_id: conversation.id + 1 })
    allow(ActionCable.server).to receive(:broadcast)

    get admin_whatsapp_conversation_path(conversation)

    expect(mine.reload.read_at).to be_present
    expect(other.reload.read_at).to be_nil
    expect(ActionCable.server).to have_received(:broadcast).with(InAppNotification.stream_name(admin.id), event: "read", ids: [mine.id], unread_count: 1)
  end

  it "marca os formularios do painel para envio sem recarregar a tela" do
    get admin_whatsapp_conversation_path(conversation)

    expect(response.body).to include('data-action="submit-&gt;wa-thread#contextSubmit"').or include('data-action="submit->wa-thread#contextSubmit"')
    expect(response.body.scan("data-wa-context-form").size).to be >= 3 # finalizar, anotação, nova tarefa
  end

  it "mostra tarefas e anotacoes do lead do atendimento e salva uma anotacao" do
    get admin_whatsapp_conversation_path(conversation)
    expect(response.body).to include("Tarefas").and include("Anotações")

    post add_note_admin_whatsapp_conversation_path(conversation), params: { body: "Cliente quer 3 quartos" }

    expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation))
    note = lead.activities.where(kind: "note").last
    expect(note.metadata).to include("body" => "Cliente quer 3 quartos", "by" => admin.name)

    get admin_whatsapp_conversation_path(conversation)
    expect(response.body).to include("Cliente quer 3 quartos")
  end

  it "finaliza o atendimento enviando a mensagem pronta" do
    allow(Whatsapp::ServiceWindowGuard).to receive(:call).and_return(double(locked?: false))

    post finish_attendance_admin_whatsapp_conversation_path(conversation)

    expect(response).to redirect_to(admin_whatsapp_conversation_path(conversation))
    expect(attendance.reload.status).to eq("closed")
    expect(attendance.closed_by).to eq(admin)
    expect(conversation.messages.outbound.last.body).to eq("Até logo!")
  end

  it "finaliza sem enviar e avisa quando a janela de 24h esta fechada" do
    allow(Whatsapp::ServiceWindowGuard).to receive(:call).and_return(double(locked?: true))

    post finish_attendance_admin_whatsapp_conversation_path(conversation)

    expect(attendance.reload.status).to eq("closed")
    expect(conversation.messages.outbound.count).to eq(0)
    expect(flash[:alert]).to include("janela de 24h")
  end

  it "mostra o sino com a contagem e marca como lida" do
    notification = InAppNotification.notify!(admin_user: admin, kind: "whatsapp_attendance", title: "Novo atendimento", body: "Comprar", url: "/x")

    get admin_whatsapp_conversations_path
    expect(response.body).to include("ax-notifications__badge")
    expect(response.body).to include("Novo atendimento")

    post read_admin_in_app_notification_path(notification)
    expect(JSON.parse(response.body)).to eq("unread_count" => 0)
    expect(notification.reload.read_at).to be_present
  end
end
