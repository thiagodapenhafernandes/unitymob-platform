require "rails_helper"

RSpec.describe PublicSearch::FriendlyUrl do
  it "converte segmentos amigáveis em params da busca pública" do
    tenant = Tenant.default
    create(:habitation, tenant:, categoria: "Apartamento")
      .tap { |habitation| habitation.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }

    params = described_class.new(tenant:).params_for(
      friendly_transaction: "venda",
      friendly_categories: "apartamento",
      friendly_locations: "centro-balneario-camboriu+blumenau",
      friendly_characteristics: "frente-mar+mobiliado"
    )

    expect(params).to include(
      transaction_type: "venda",
      category: ["Apartamento"],
      characteristics: ["frente_mar", "mobiliado"]
    )
    expect(params[:city]).to include("Centro - Balneário Camboriú", "blumenau")
  end

  it "usa todos como segmento posicional vazio" do
    params = described_class.new(tenant: Tenant.default).params_for(
      friendly_transaction: "alugar",
      friendly_categories: "todos",
      friendly_locations: "todos",
      friendly_characteristics: "vista-mar"
    )

    expect(params).to eq(
      transaction_type: "aluguel",
      characteristics: ["vista_mar"]
    )
  end
end
