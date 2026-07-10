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
end
