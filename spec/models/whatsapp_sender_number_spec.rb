require "rails_helper"

RSpec.describe WhatsappSenderNumber, type: :model do
  {
    "15559878827" => "+15559878827",
    "+15559878827" => "+15559878827",
    "554733111067" => "55 (47) 3311-1067",
    "5547991427176" => "55 (47) 99142-7176"
  }.each do |stored, displayed|
    it "exibe #{stored} respeitando o DDI sem alterar o cadastro" do
      sender = described_class.new(label: "Remetente", display_phone_number: stored)

      expect(sender.formatted_phone).to eq(displayed)
      expect(sender.display_label).to eq("Remetente · #{displayed}")
      expect(sender.display_phone_number).to eq(stored)
    end
  end

  it "mantém apenas um número ativo para notificações do sistema por tenant" do
    first = create(:whatsapp_sender_number, label: "Notificações A", phone_number_id: "1001", use_for_notifications: true)
    second = create(:whatsapp_sender_number, label: "Notificações B", phone_number_id: "1002", use_for_notifications: true)

    expect(first.reload.use_for_notifications?).to eq(false)
    expect(second.reload.use_for_notifications?).to eq(true)
  end

  it "mantém campanhas usando qualquer número ativo" do
    first = create(:whatsapp_sender_number, label: "Campanhas A", phone_number_id: "2001", use_for_notifications: true)
    second = create(:whatsapp_sender_number, label: "Campanhas B", phone_number_id: "2002", use_for_notifications: false)

    expect(described_class.default_for_campaign(Tenant.default)).to eq(first)
    expect(Tenant.default.whatsapp_sender_numbers.active).to include(first, second)
  end
end
