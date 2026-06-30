require "rails_helper"

RSpec.describe Vista::ApiPictureMaterializationService, type: :service do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  describe ".default_scope" do
    it "inclui unidade que usa fotos do empreendimento como fallback publico" do
      development = create(:habitation, codigo: "611", tipo: "Empreendimento", pictures: [])
      habitation = create(
        :habitation,
        pictures: [],
        fotos_empreendimento: [
          {
            "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/611/foto.jpg",
            "ordem" => 1
          }
        ],
        use_development_photos_flag: true,
        codigo_empreendimento: development.codigo,
        imovel_dwv: "Nao",
        address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
      )

      expect(described_class.default_scope).to include(habitation)
    end
  end

  describe "#call" do
    it "processa fotos de empreendimento quando a unidade usa esse fallback" do
      development = create(:habitation, codigo: "611", tipo: "Empreendimento", pictures: [])
      habitation = create(
        :habitation,
        pictures: [],
        fotos_empreendimento: [
          {
            "url" => "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/611/foto.jpg",
            "ordem" => 1
          }
        ],
        use_development_photos_flag: true,
        codigo_empreendimento: development.codigo,
        imovel_dwv: "Nao",
        address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
      )

      result = described_class.new(scope: Habitation.where(id: habitation.id), dry_run: true).call

      expect(result.properties_scanned).to eq(1)
      expect(result.pictures_scanned).to eq(1)
      expect(result.pending_download).to eq(1)
    end
  end
end
