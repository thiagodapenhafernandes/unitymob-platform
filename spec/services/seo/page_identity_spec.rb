require "rails_helper"

RSpec.describe Seo::PageIdentity do
  describe ".sanitize_path" do
    {
      "/" => "/",
      "/imoveis/apartamento%20centro" => "/imoveis/apartamento%20centro",
      "/imoveis/ação" => "/imoveis/ação",
      "//imoveis/apartamento" => "//imoveis/apartamento",
      "/imoveis/invalid%zz" => "/imoveis/invalid%zz",
      "/imoveis/com espaço" => "/imoveis/com espaço",
      "/imoveis#galeria" => "/imoveis",
      "imoveis" => "/imoveis",
      "https://example.test/imoveis?utm_source=google&city=Recife" => "/imoveis?city=Recife",
      "/imoveis?city=Recife&class=absolute&city=Recife&category=Casa" => "/imoveis?category=Casa&city=Recife"
    }.each do |input, expected|
      it "preserves canonical normalization for #{input.inspect}" do
        expect(described_class.sanitize_path(input)).to eq(expected)
      end
    end
  end
end
