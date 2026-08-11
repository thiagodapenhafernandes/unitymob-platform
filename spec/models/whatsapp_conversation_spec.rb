require "rails_helper"

RSpec.describe WhatsappConversation, type: :model do
  it "normaliza telefone de contato antes de validar" do
    conversation = described_class.new(contact_phone: "47 9972-9441", status: "open")

    expect(conversation).to be_valid
    expect(conversation.contact_phone).to eq("5547999729441")
  end

  it "monta link de WhatsApp sem duplicar DDI" do
    conversation = described_class.new(contact_phone: "5547999729441", status: "open")

    expect(conversation.whatsapp_link).to eq("https://wa.me/5547999729441")
  end

  it "identifica conversas abertas aguardando resposta da equipe" do
    tenant = Tenant.create!(name: "Tenant WhatsApp #{SecureRandom.hex(3)}", slug: "tenant-whatsapp-#{SecureRandom.hex(3)}")
    pending = described_class.create!(tenant: tenant, contact_phone: "5547999991001", status: "open")
    answered = described_class.create!(tenant: tenant, contact_phone: "5547999991002", status: "open")
    closed = described_class.create!(tenant: tenant, contact_phone: "5547999991003", status: "closed")

    pending.messages.create!(tenant: tenant, direction: "outbound", body: "Olá", created_at: 2.hours.ago, updated_at: 2.hours.ago)
    pending.messages.create!(tenant: tenant, direction: "inbound", body: "Tenho interesse", created_at: 1.hour.ago, updated_at: 1.hour.ago)
    answered.messages.create!(tenant: tenant, direction: "inbound", body: "Tenho interesse", created_at: 2.hours.ago, updated_at: 2.hours.ago)
    answered.messages.create!(tenant: tenant, direction: "outbound", body: "Vamos falar", created_at: 1.hour.ago, updated_at: 1.hour.ago)
    closed.messages.create!(tenant: tenant, direction: "inbound", body: "Oi", created_at: 30.minutes.ago, updated_at: 30.minutes.ago)

    expect(described_class.where(tenant: tenant).pending_reply_since(1.day.ago)).to contain_exactly(pending)
  end
end
