require "rails_helper"

RSpec.describe Admin::HabitationDevelopmentFilterOptions do
  describe ".call" do
    it "inclui empreendimentos reais e nomes sem pai sem duplicar por nome" do
      tenant = Tenant.create!(name: "Tenant filtro #{SecureRandom.hex(4)}", slug: "tenant-filtro-#{SecureRandom.hex(4)}")
      create(
        :habitation,
        tenant: tenant,
        codigo: "DEV-VERMONT",
        tipo: "Empreendimento",
        categoria: "Empreendimento",
        nome_empreendimento: "Vermont"
      )
      create(
        :habitation,
        tenant: tenant,
        codigo: "UNIT-VERMONT-1",
        tipo: "Unitário",
        categoria: "Apartamento",
        codigo_empreendimento: nil,
        nome_empreendimento: "Vermont"
      )
      create(
        :habitation,
        tenant: tenant,
        codigo: "UNIT-ORPHAN-1",
        tipo: "Unitário",
        categoria: "Apartamento",
        codigo_empreendimento: nil,
        nome_empreendimento: "Residencial Sem Pai"
      )
      create(
        :habitation,
        tenant: tenant,
        codigo: "UNIT-ORPHAN-2",
        tipo: "Unitário",
        categoria: "Apartamento",
        codigo_empreendimento: nil,
        nome_empreendimento: "residencial sem pai"
      )

      options = described_class.call(tenant.habitations)

      expect(options).to include(["Vermont", "dev:DEV-VERMONT"])
      expect(options).to include(["Residencial Sem Pai", "name:Residencial Sem Pai"])
      expect(options.count { |label, _value| I18n.transliterate(label).downcase == "vermont" }).to eq(1)
      expect(options.count { |label, _value| I18n.transliterate(label).downcase == "residencial sem pai" }).to eq(1)
    end
  end

  describe ".parse" do
    it "identifica valores novos e preserva valores legados" do
      expect(described_class.parse("dev:123")).to eq(type: :development, value: "123")
      expect(described_class.parse("name:Vermont")).to eq(type: :standalone, value: "Vermont")
      expect(described_class.parse("Vermont")).to eq(type: :legacy, value: "Vermont")
    end
  end
end
