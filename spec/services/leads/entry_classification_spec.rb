require "rails_helper"

RSpec.describe Leads::EntryClassification do
  let(:tenant) { Tenant.default }
  let(:lead) { build(:lead, tenant: tenant, origin: "RD Station", product: nil, other_information: {}) }

  it "usa a modalidade estruturada antes de texto antigo conflitante" do
    lead.other_information = {"business_type" => "sale", "rd_station_payload" => {"interest" => "aluguel"}}
    expect(described_class.new(lead).business_type).to eq(:venda)
  end

  it "não usa nome de campanha, status ou observações antigas como modalidade" do
    lead.notes = "Comprar apartamento"
    lead.other_information = {"meta_campaign_name" => "Venda Gralha Azul", "rd_station_campaign_name" => "Venda Gralha Azul"}
    expect(described_class.new(lead).business_type).to be_nil
  end

  it "reconhece imóvel de locação da própria conta" do
    property = create(:habitation, tenant: tenant, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 350000)
    lead.property_id = property.id
    expect(described_class.new(lead).business_type).to eq(:locacao)
  end

  it "não usa imóvel de outra conta" do
    other = Tenant.create!(name: "Outra classificação", slug: "classification-other")
    property = create(:habitation, tenant: other, status: "Venda", valor_venda_cents: 50000000)
    lead.property_id = property.id
    expect(described_class.new(lead).business_type).to be_nil
  end

  it "ignora UTMs de campanha ao classificar a URL e tolera URL inválida" do
    lead.source_url = "https://example.test/imoveis?utm_campaign=venda"
    expect(described_class.new(lead).business_type).to be_nil
    lead.source_url = "https://bad url"
    expect(described_class.new(lead).business_type).to be_nil
  end

  it "reconhece ambas as modalidades sem escolher uma delas" do
    lead.product = "Venda e locação de apartamento"
    expect(described_class.new(lead).business_type).to eq(:ambos)
  end

  it "identifica pedido administrativo e mantém contato sem intenção em triagem" do
    lead.other_information = {"whatsapp_service_contact" => true}
    lead.product = "Financeiro: segunda via do boleto"
    expect(described_class.new(lead).nature).to eq(:administrative)
    lead.product = "Olá"
    expect(described_class.new(lead).nature).to eq(:unknown)
  end

  it "não trata informação de manutenção de imóvel como pedido administrativo" do
    lead.product = "Comprar apartamento sem necessidade de manutenção"
    expect(described_class.new(lead).nature).to eq(:commercial)
    expect(described_class.new(lead).business_type).to eq(:venda)
  end
end
