require "rails_helper"

# Subscrição no thread exige a mesma visibilidade dono/equipe do HTTP:
# conversa fora do visible_to é rejeitada sem abrir stream.
RSpec.describe WhatsappConversationChannel, type: :channel do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:tenant) { Tenant.create!(name: "Canal #{SecureRandom.hex(3)}", slug: "canal-#{SecureRandom.hex(6)}") }
  let(:profile) do
    tenant.profiles.create!(name: "Atendente WhatsApp", axis: "vertical", position: 300,
                            permissions: { "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" } })
  end
  let(:agent) { create(:admin_user, tenant: tenant, profile: profile) }
  let(:other_broker) { create(:admin_user, tenant: tenant) }
  let(:own_conversation) do
    tenant.whatsapp_conversations.create!(contact_phone: "5547999990201", contact_name: "Cliente Próprio",
                                          assigned_admin_user: agent)
  end
  let(:other_conversation) do
    tenant.whatsapp_conversations.create!(contact_phone: "5547999990202", contact_name: "Cliente Alheio",
                                          assigned_admin_user: other_broker)
  end

  before { stub_connection(current_admin_user: agent) }

  it "rejeita subscrição em conversa de outro dono sem abrir stream" do
    subscribe(conversation_id: other_conversation.id)

    expect(subscription).to be_rejected
  end

  it "confirma subscrição em conversa do próprio escopo" do
    subscribe(conversation_id: own_conversation.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(
      Whatsapp::ThreadBroadcaster.stream_name(own_conversation, focus_mode: false)
    )
  end

  it "rejeita subscrição em conversa de outra conta" do
    foreign_tenant = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(6)}")
    foreign = foreign_tenant.whatsapp_conversations.create!(contact_phone: "5511988880203", contact_name: "Cliente Alheio")

    subscribe(conversation_id: foreign.id)

    expect(subscription).to be_rejected
  end
end
