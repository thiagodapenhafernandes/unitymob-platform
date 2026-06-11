require "rails_helper"

RSpec.describe WhatsappBusinessIntegration, type: :model do
  it "considera conectado apenas com status, WABA e telefone" do
    integration = build(:whatsapp_business_integration)

    expect(integration.connected?).to be(true)

    integration.phone_number_id = nil
    expect(integration.connected?).to be(false)
  end

  it "exibe apenas um preview do token" do
    integration = build(:whatsapp_business_integration, access_token: "TOKEN-SUPER-SECRETO")

    expect(integration.token_preview).to eq("...ECRETO")
  end

  it "define telefone por tipo de negociacao do site" do
    integration = build(:whatsapp_business_integration)

    expect(integration.phone_for("sale")).to eq("5547991111111")
    expect(integration.phone_for("rent")).to eq("5547992222222")
    expect(integration.phone_for("sale_rent")).to eq("5547993333333")
  end

  it "usa o telefone padrao quando o tipo de negociacao nao tem numero especifico" do
    integration = build(:whatsapp_business_integration, sale_whatsapp_number: nil, default_whatsapp_number: "(47) 3311-1067")

    expect(integration.phone_for("sale")).to eq("554733111067")
  end

  it "controla se o formulario intermediario deve aparecer por negociacao" do
    integration = build(:whatsapp_business_integration, rent_requires_lead_form: false)

    expect(integration.requires_form_for?("sale")).to be(true)
    expect(integration.requires_form_for?("rent")).to be(false)
  end

  it "monta url do WhatsApp usando a negociacao do imovel" do
    integration = build(:whatsapp_business_integration)
    habitation = build(:habitation, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 5_000_00)

    expect(integration.whatsapp_url_for(habitation: habitation, message: "Olá")).to include("https://wa.me/5547992222222")
  end
end
