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
  describe "preço final por mensagens entregues" do
    let(:sender) { build(:whatsapp_sender_number, cpl_sent_unit_price: 0.59, cpl_fla_unit_price: 0.12, meta_brl_exchange_rate: 5, meta_exchange_currency: "USD") }

    it "converte o custo oficial e embute o adicional somente no volume entregue" do
      expect(sender.customer_delivery_total(meta_amount: "0.4375", currency: "USD", delivered: 7)).to eq(BigDecimal("6.3175"))
    end

    it "usa somente o custo da Meta quando o adicional é zero" do
      sender.cpl_sent_unit_price = 0
      expect(sender.customer_delivery_total(meta_amount: "0.4375", currency: "USD", delivered: 7)).to eq(BigDecimal("2.1875"))
    end

    it "não inventa custo sem o valor da Meta ou sem cotação" do
      expect(sender.customer_delivery_total(meta_amount: nil, currency: "USD", delivered: 7)).to be_nil
      sender.meta_brl_exchange_rate = nil
      expect(sender.customer_delivery_total(meta_amount: "0.4375", currency: "USD", delivered: 7)).to be_nil
    end

    it "exige nova cotação quando a moeda Meta muda" do
      expect(sender.customer_delivery_total(meta_amount: 1, currency: "EUR", delivered: 2)).to be_nil
    end

    it "não converte novamente valores já em reais" do
      expect(sender.customer_delivery_total(meta_amount: 1, currency: "BRL", delivered: 2)).to eq(BigDecimal("2.18"))
    end

    it "não cobra falhas nem mensagens não entregues" do
      expect(sender.customer_delivery_total(meta_amount: 0, currency: "BRL", delivered: 0)).to eq(0)
    end

    it "recusa cotação negativa e começa novos números sem adicional" do
      sender.meta_brl_exchange_rate = -1
      expect(sender).not_to be_valid
      expect(described_class.new.cpl_sent_unit_price).to eq(0)
    end
  end

end
