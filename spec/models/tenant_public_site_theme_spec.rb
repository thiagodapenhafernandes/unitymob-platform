require "rails_helper"

RSpec.describe Tenant, type: :model do
  describe ".public_site_theme_definitions" do
    it "descobre as folhas do diretório com stylesheet resolvível" do
      defs = described_class.public_site_theme_definitions

      expect(defs.keys).to include("default", "saluteimoveis", "conexaoimobiliaria")
      defs.each_value do |config|
        expect(config[:stylesheet]).to start_with("public_site_themes/")
        expect(config[:label]).to be_present
      end
    end

    it "mantém rótulos conhecidos e humaniza arquivos novos" do
      allow(Dir).to receive(:children).and_return(["default.css", "vitrine_nova.css"])

      defs = described_class.public_site_theme_definitions

      expect(defs["default"][:label]).to eq("Padrão")
      expect(defs["vitrine_nova"][:label]).to eq("Vitrine nova")
      expect(defs["vitrine_nova"][:stylesheet]).to eq("public_site_themes/vitrine_nova")
    end
  end

  describe "gating por conta" do
    it "nunca expõe skin fora do trio conhecido para conta nova" do
      tenant = described_class.create!(name: "Conta Temas #{SecureRandom.hex(3)}")

      expect(tenant.available_public_site_themes.keys - %w[default saluteimoveis conexaoimobiliaria]).to be_empty
    end
  end

  describe "tema de conta nova" do
    it "nasce no default mesmo se o padrão da coluna no banco estiver em outro tema" do
      # DDL dentro da transação do teste: o Postgres desfaz no rollback.
      described_class.connection.change_column_default(:tenants, :public_site_theme, "saluteimoveis")
      described_class.reset_column_information

      tenant = described_class.create!(name: "Imobiliária Nova", slug: "imobiliaria-nova-#{SecureRandom.hex(3)}")

      expect(tenant.public_site_theme).to eq("default")
      expect(tenant.public_site_stylesheet).to eq("public_site_themes/default")
    ensure
      described_class.reset_column_information
    end

    it "continua inferindo o tema pelo nome da conta" do
      tenant = described_class.create!(name: "Conexão Imobiliária", slug: "conexao-#{SecureRandom.hex(3)}")

      expect(tenant.public_site_theme).to eq("conexaoimobiliaria")
    end
  end
end
