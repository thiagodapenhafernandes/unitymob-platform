require "rails_helper"

RSpec.describe Habitation, type: :model do
  describe ".next_automatic_codigo" do
    it "continues the CRM sequence after the highest imported Vista reference" do
      create(:habitation, codigo: "8628", imovel_dwv: "Nao", last_sync_message: "Importado do dump Vista")
      create(:habitation, codigo: "DWV-9999", imovel_dwv: "Sim")

      expect(described_class.next_automatic_codigo).to eq("8629")
    end

    it "skips numeric codes that are already occupied" do
      create(:habitation, codigo: "8628", imovel_dwv: "Nao", last_sync_message: "Importado do dump Vista")
      create(:habitation, codigo: "8629", imovel_dwv: "Nao")

      expect(described_class.next_automatic_codigo).to eq("8630")
    end
  end

  describe "#assign_codigo_automaticamente" do
    it "fills blank codigo with the next CRM sequence value on create" do
      create(:habitation, codigo: "8628", imovel_dwv: "Nao", last_sync_message: "Importado do dump Vista")

      habitation = described_class.create!(categoria: "Apartamento")

      expect(habitation.codigo).to eq("8629")
    end
  end

  describe "#data_cadastro_crm" do
    it "sets the registration date on create when it is blank" do
      habitation = described_class.create!(categoria: "Apartamento")

      expect(habitation.data_cadastro_crm).to be_present
    end

    it "keeps an imported registration date when present" do
      imported_at = 3.years.ago.change(usec: 0)
      habitation = described_class.create!(categoria: "Apartamento", data_cadastro_crm: imported_at)

      expect(habitation.data_cadastro_crm.to_i).to eq(imported_at.to_i)
    end
  end

  describe "third-party commercial values" do
    it "stores formatted third-party values in cents" do
      habitation = described_class.new(
        valor_alugado_terceiros_formatted: "R$ 4.500,00",
        valor_vendido_terceiros_formatted: "R$ 980.000,00"
      )

      expect(habitation.valor_alugado_terceiros_cents).to eq(450_000)
      expect(habitation.valor_vendido_terceiros_cents).to eq(98_000_000)
    end

    it "clears formatted money values when the submitted value is blank" do
      habitation = create(:habitation, valor_venda_cents: 500_000_00)

      habitation.update!(valor_venda_formatted: "")

      expect(habitation.reload.valor_venda_cents).to be_nil
    end
  end

  describe "broker intake address complement rules" do
    it "requires complement for category-specific intakes without treating street houses as mandatory complement" do
      expect(described_class.new(categoria: "Apartamento")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Casa em Condomínio")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Sala Comercial")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Terreno")).to be_requires_intake_address_complement
      expect(described_class.new(categoria: "Casa")).not_to be_requires_intake_address_complement
    end

    it "allows the owner broker or assigned broker to release a broker intake" do
      owner = create(:admin_user)
      assigned = create(:admin_user)
      outsider = create(:admin_user)
      habitation = create(:habitation, :broker_intake, admin_user: owner, intake_status: "admin_approved")
      habitation.broker_assignments.create!(admin_user: assigned, role: "captador")

      expect(habitation).to be_broker_release_pending
      expect(habitation.broker_responsible_for?(owner)).to be(true)
      expect(habitation.broker_responsible_for?(assigned)).to be(true)
      expect(habitation.broker_responsible_for?(outsider)).to be(false)
    end
  end

  describe "#inactive_for_admin_card?" do
    it "does not mark active internal properties as inactive cards" do
      habitation = described_class.new(status: "Aluguel", exibir_no_site_flag: false)

      expect(habitation).not_to be_inactive_for_admin_card
    end

    it "marks unavailable statuses as inactive cards" do
      expect(described_class.new(status: "Suspenso", exibir_no_site_flag: true)).to be_inactive_for_admin_card
      expect(described_class.new(status: "Vendido terceiros", exibir_no_site_flag: true)).to be_inactive_for_admin_card
      expect(described_class.new(status: "Alugado imobiliária", exibir_no_site_flag: true)).to be_inactive_for_admin_card
    end
  end

  describe "#unavailable_for_duplicate_check?" do
    it "keeps hidden-from-site properties unavailable for duplicate blocking" do
      habitation = described_class.new(status: "Aluguel", exibir_no_site_flag: false)

      expect(habitation).to be_unavailable_for_duplicate_check
    end
  end

  describe "#capture_price_reductions" do
    it "stores previous sale price and promotional value when sale price decreases" do
      habitation = create(:habitation, valor_venda_cents: 1_000_000_00, valor_promocional_cents: nil)

      habitation.update!(valor_venda_cents: 900_000_00)

      expect(habitation).to have_attributes(
        valor_venda_anterior_cents: 1_000_000_00,
        valor_promocional_cents: 900_000_00
      )
    end

    it "stores previous rent price and promotional value when rent price decreases" do
      habitation = create(:habitation, valor_venda_cents: 0, valor_locacao_cents: 6_000_00, valor_promocional_cents: nil)

      habitation.update!(valor_locacao_cents: 5_500_00)

      expect(habitation).to have_attributes(
        valor_locacao_anterior_cents: 6_000_00,
        valor_promocional_cents: 5_500_00
      )
    end
  end
end
