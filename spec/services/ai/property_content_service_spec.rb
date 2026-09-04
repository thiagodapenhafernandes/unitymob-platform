require "rails_helper"

RSpec.describe Ai::PropertyContentService do
  describe "payload de geração" do
    it "inclui parâmetros configuráveis da OpenAI" do
      habitation = create(:habitation)
      Setting.set(described_class::TEMPERATURE_SETTING, "0.33", "Temperature", tenant: habitation.tenant)
      Setting.set(described_class::TOP_P_SETTING, "0.77", "Top P", tenant: habitation.tenant)
      Setting.set(described_class::FREQUENCY_PENALTY_SETTING, "0.44", "Frequency penalty", tenant: habitation.tenant)
      Setting.set(described_class::PRESENCE_PENALTY_SETTING, "0.22", "Presence penalty", tenant: habitation.tenant)

      payload = described_class.new(habitation).send(:openai_payload)

      expect(payload).to include(
        temperature: 0.33,
        top_p: 0.77,
        frequency_penalty: 0.44,
        presence_penalty: 0.22
      )
    end

    it "inclui todos os campos de endereço relevantes para a IA" do
      habitation = create(
        :habitation,
        bloco: "B",
        lote: "12",
        quadra: "Q7",
        public_map_display_mode: "approximate",
        public_street_view_mode: "disabled"
      )
      habitation.address.update!(
        tipo_endereco: "Avenida",
        logradouro: "João da Costa",
        numero: "123",
        complemento: "Distrito Rio do Meio",
        bairro: "Distrito de Águas Brancas",
        bairro_comercial: "Águas Brancas",
        cidade: "Camboriú",
        uf: "SC",
        cep: "88340-000",
        pais: "Brasil",
        latitude: -27.024,
        longitude: -48.653,
        imediacoes: ["Mercado", "Escola"]
      )

      payload = described_class.new(habitation).send(:property_payload)

      expect(payload.fetch(:endereco)).to include(
        tipo_endereco: "Avenida",
        logradouro: "João da Costa",
        numero: "123",
        complemento: "Distrito Rio do Meio",
        bairro: "Distrito de Águas Brancas",
        bairro_comercial: "Águas Brancas",
        cidade: "Camboriú",
        uf: "SC",
        cep: "88340-000",
        pais: "Brasil",
        bloco: "B",
        lote: "12",
        quadra: "Q7",
        imediacoes: ["Mercado", "Escola"],
        localizacao_publica: "approximate",
        vista_da_rua: "disabled"
      )
    end
  end
end
