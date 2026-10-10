require "rails_helper"

# Quem perde o atendimento perde o stream: a troca de dono derruba o cable do
# dono anterior para o thread aberto parar de receber conteúdo da conversa.
RSpec.describe Whatsapp::AttendanceManager do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:tenant) { Tenant.create!(name: "Revogação #{SecureRandom.hex(3)}", slug: "revog-#{SecureRandom.hex(6)}") }
  let(:profile) do
    tenant.profiles.create!(name: "Atendente WhatsApp", axis: "vertical", position: 300,
                            permissions: { "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" } })
  end
  let(:previous_owner) { create(:admin_user, tenant: tenant, profile: profile) }
  let(:new_owner) { create(:admin_user, tenant: tenant) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: previous_owner, phone: "5547999990301") }
  let(:conversation) do
    tenant.whatsapp_conversations.create!(contact_phone: "5547999990301", contact_name: "Cliente Transferido",
                                          lead: lead, assigned_admin_user: previous_owner)
  end
  let!(:attendance) do
    conversation.attendances.create!(tenant: tenant, lead: lead, admin_user: previous_owner,
                                     button_text: "Assunto", status: "open", opened_at: 1.hour.ago)
  end
  let(:remote_connections) { double("remote_connections") }
  let(:scoped_connections) { double("scoped_connections") }

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(ActionCable.server).to receive(:remote_connections).and_return(remote_connections)
    allow(remote_connections).to receive(:where).and_return(scoped_connections)
    allow(scoped_connections).to receive(:disconnect)
  end

  it "transfer! desconecta o cable do dono anterior" do
    described_class.transfer!(attendance, to: new_owner, by: previous_owner)

    expect(attendance.reload.admin_user).to eq(new_owner)
    expect(remote_connections).to have_received(:where).with(current_admin_user: previous_owner)
    expect(scoped_connections).to have_received(:disconnect)
  end

  it "dono anterior de escopo próprio perde a visibilidade da conversa transferida" do
    expect(WhatsappConversation.visible_to(previous_owner).exists?(conversation.id)).to be(true)

    described_class.transfer!(attendance, to: new_owner, by: previous_owner)

    expect(WhatsappConversation.visible_to(previous_owner).exists?(conversation.id)).to be(false)
  end

  it "falha no cable não quebra a transferência" do
    allow(remote_connections).to receive(:where).and_raise(StandardError, "redis down")

    expect { described_class.transfer!(attendance, to: new_owner, by: previous_owner) }.not_to raise_error
    expect(attendance.reload.admin_user).to eq(new_owner)
  end
end
