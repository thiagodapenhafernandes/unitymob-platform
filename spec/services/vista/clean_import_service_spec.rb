require "rails_helper"

RSpec.describe Vista::CleanImportService do
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
