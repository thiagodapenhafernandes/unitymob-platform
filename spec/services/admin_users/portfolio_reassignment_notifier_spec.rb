require "rails_helper"

RSpec.describe AdminUsers::PortfolioReassignmentNotifier do
  let(:tenant) { Tenant.create!(name: "Tenant notifica #{SecureRandom.hex(3)}", slug: "tenant-notifica-#{SecureRandom.hex(3)}") }
  let(:target) { create(:admin_user, tenant: tenant) }

  it "cria uma única notificação com os totais agregados" do
    expect {
      described_class.call(target: target, leads_count: 70, habitations_count: 20, from_user_name: "Corretor 2")
    }.to change { InAppNotification.where(admin_user: target).count }.by(1)

    notification = InAppNotification.where(admin_user: target).last
    expect(notification.kind).to eq("portfolio_reassigned")
    expect(notification.title).to eq("Você recebeu uma carteira")
    expect(notification.body).to eq("Foram atribuídos a você 20 imóveis e 70 leads (carteira de Corretor 2).")
    expect(notification.url).to eq("/admin/leads")
    expect(notification.metadata).to include("leads_count" => 70, "habitations_count" => 20)
  end

  it "usa singular e aponta para imóveis quando só há imóveis" do
    described_class.call(target: target, leads_count: 0, habitations_count: 1, from_user_name: "Corretor 2")

    notification = InAppNotification.where(admin_user: target).last
    expect(notification.body).to eq("Foram atribuídos a você 1 imóvel (carteira de Corretor 2).")
    expect(notification.url).to eq("/admin/habitations")
  end

  it "não notifica quando nada foi transferido" do
    expect {
      described_class.call(target: target, leads_count: 0, habitations_count: 0, from_user_name: "Corretor 2")
    }.not_to change { InAppNotification.count }
  end

  it "não notifica sem usuário destino" do
    expect(described_class.call(target: nil, leads_count: 5, habitations_count: 1, from_user_name: "X")).to be_nil
    expect(InAppNotification.count).to eq(0)
  end
end
