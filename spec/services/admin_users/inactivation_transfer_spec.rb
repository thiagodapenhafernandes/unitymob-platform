require "rails_helper"

# Inativação derruba as conexões ActionCable do usuário: streams já abertos
# (conversas, inbox) não re-autenticam sozinhos.
RSpec.describe AdminUsers::InactivationTransfer do
  let(:user) { create(:admin_user) }
  let(:target) { create(:admin_user, tenant: user.tenant) }
  let(:remote_connections) { double("remote_connections") }
  let(:scoped_connections) { double("scoped_connections") }

  before do
    allow(ActionCable.server).to receive(:remote_connections).and_return(remote_connections)
    allow(remote_connections).to receive(:where).and_return(scoped_connections)
    allow(scoped_connections).to receive(:disconnect)
  end

  it "desconecta o cable do usuário inativado" do
    described_class.call(user: user, target: target, mode: "reassign")

    expect(user.reload.active).to be(false)
    expect(remote_connections).to have_received(:where).with(current_admin_user: user)
    expect(scoped_connections).to have_received(:disconnect)
  end

  it "falha no cable não quebra a inativação" do
    allow(remote_connections).to receive(:where).and_raise(StandardError, "redis down")

    expect { described_class.call(user: user, target: target, mode: "reassign") }.not_to raise_error
    expect(user.reload.active).to be(false)
  end

  it "não desconecta quando a validação falha" do
    expect { described_class.call(user: user, target: nil, mode: "reassign") }
      .to raise_error(AdminUsers::InactivationTransfer::Error)
    expect(remote_connections).not_to have_received(:where)
  end
end
