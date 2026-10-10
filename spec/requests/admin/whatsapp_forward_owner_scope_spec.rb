require "rails_helper"

# Forward respeita o mesmo recorte dono/equipe da conversa de origem:
# o destino fora do escopo rende 404 sem criar mensagem, sem disparar e sem vazar o nome.
RSpec.describe "Admin::WhatsappInbox forward owner scope", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-fwd-#{SecureRandom.hex(6)}@salute.test") }
  let(:tenant) { admin.tenant }
  let(:profile) do
    tenant.profiles.create!(name: "Atendente WhatsApp", axis: "vertical", position: 300,
                            permissions: { "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" } })
  end
  let(:agent) { create(:admin_user, tenant: tenant, profile: profile) }
  let(:other_broker) { create(:admin_user, tenant: tenant) }
  let(:source) do
    tenant.whatsapp_conversations.create!(contact_phone: "5547999990101", contact_name: "Cliente Próprio",
                                          assigned_admin_user: agent)
  end
  let!(:source_message) { source.messages.create!(direction: "inbound", body: "Olá, preciso de ajuda", status: "delivered") }
  let(:target) do
    tenant.whatsapp_conversations.create!(contact_phone: "5547999990102", contact_name: "Cliente Alheio Secreto",
                                          assigned_admin_user: other_broker)
  end

  before do
    host! "localhost"
    sign_in agent
    allow(Whatsapp::SendMessageJob).to receive(:dispatch)
    allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
  end

  def forward_path(source_conversation, message)
    "/admin/atendimento/whatsapp/#{source_conversation.id}/messages/#{message.id}/forward"
  end

  it "recusa forward para conversa de outro dono com 404, sem criar mensagem nem disparar" do
    expect do
      post forward_path(source, source_message), params: { target_conversation_id: target.id }
    end.not_to change { target.messages.count }

    expect(response).to have_http_status(:not_found)
    expect(Whatsapp::SendMessageJob).not_to have_received(:dispatch)
    expect(response.body).not_to include("Cliente Alheio Secreto")
  end

  it "permite forward para conversa do próprio escopo" do
    own_target = tenant.whatsapp_conversations.create!(contact_phone: "5547999990103", contact_name: "Outro Cliente Próprio",
                                                       assigned_admin_user: agent)

    expect do
      post forward_path(source, source_message), params: { target_conversation_id: own_target.id }
    end.to change { own_target.messages.count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("ok" => true, "target_name" => "Outro Cliente Próprio")
    expect(Whatsapp::SendMessageJob).to have_received(:dispatch)
  end
end
