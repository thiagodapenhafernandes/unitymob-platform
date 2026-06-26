require "rails_helper"

RSpec.describe Vista::CleanImportService do
  describe "publication flag preservation" do
    it "não sobrescreve publicação local de imóvel existente no import raw" do
      batch = VistaImportBatch.create!(dump_dir: "spec-vista", status: "completed")
      habitation = create(:habitation, codigo: "9001", categoria: "Apartamento", exibir_no_site_flag: false)
      VistaRawRecord.create!(
        vista_import_batch: batch,
        table_name: "CADIMO",
        row_index: 1,
        codigo_imovel: "9001",
        payload: {
          "CODIGO" => "9001",
          "CATEGORIA" => "Apartamento",
          "ENDERECO" => "Rua 1500",
          "NUM_ENDERECO" => "10",
          "BAIRRO" => "Centro",
          "CIDADE" => "Balneário Camboriú",
          "UF" => "SC",
          "EXIBIR_NO_SITE_SALUTE" => "Sim",
          "DA_WEB" => "Sim"
        }
      )

      described_class.new(batch: batch, dry_run: false).call

      expect(habitation.reload.exibir_no_site_flag).to be(false)
    end
  end

  describe "development code mapping" do
    let(:service) { described_class.new(dry_run: true) }

    before do
      service.instance_variable_set(:@development_codes, Set.new(["1950"]))
    end

    it "uses an explicit valid Vista development code" do
      code = service.send(
        :development_code_for,
        {
          "CODIGO_EMP" => "1950",
          "EMPREENDIMENTO" => "Blue Coast Tower"
        }
      )

      expect(code).to eq("1950")
    end

    it "does not infer a development link from the Vista development name" do
      code = service.send(
        :development_code_for,
        {
          "CODIGO_EMP" => "",
          "EMPREENDIMENTO" => "Moema Ii"
        }
      )

      expect(code).to be_nil
    end
  end
end
