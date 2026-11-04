require "rails_helper"

RSpec.describe DistributionRule, type: :model do
  describe "recebimento" do
    expected = {
      venda: [:venda], locacao: [:locacao], ambos: [:venda, :locacao, :ambos], diaria: [:diaria],
      administrativo: [:administrativo], triagem: [:triagem],
      todos: [:venda, :locacao, :ambos, :diaria, :administrativo, :triagem]
    }
    expected.each do |receiving, accepted|
      it "#{receiving} recebe somente as categorias declaradas" do
        rule = build(:distribution_rule, business_type: receiving)
        expected[:todos].each do |category|
          classification = instance_double(Leads::EntryClassification,
            category: category.to_s, nature: category == :administrativo ? :administrative : (category == :triagem ? :unknown : :commercial),
            business_type: %i[administrativo triagem].include?(category) ? nil : category)
          expect(rule.accepts_entry?(classification)).to eq(accepted.include?(category)), "#{receiving}: #{category}"
        end
      end
    end
  end

  describe "coexistência de formulários explícitos" do
    let(:tenant) { Tenant.default }
    let!(:sale) { create(:distribution_rule, tenant: tenant, source_meta: true, meta_forms: ["same-form"], business_type: :venda) }

    it "permite venda e locação separadas, mas rejeita Todos sobreposto" do
      other = build(:distribution_rule, tenant: tenant, source_meta: true, meta_forms: ["same-form"], business_type: :locacao)
      expect(other).to be_valid
      other.business_type = :todos
      expect(other).not_to be_valid
      expect(other.errors[:meta_forms].join).to include(sale.name)
    end

    it "permite exceções, regra automática, regra inativa e outra conta" do
      other = build(:distribution_rule, tenant: tenant, source_meta: true, meta_forms: ["same-form"], business_type: :todos,
        excluded_meta_form_ids: ["same-form"])
      expect(other).to be_valid
      other.excluded_meta_form_ids = []
      other.auto_add_forms = true
      expect(other).to be_valid
      other.auto_add_forms = false
      other.active = false
      expect(other).to be_valid
      other.active = true
      other.tenant = Tenant.create!(name: "Outra recepção", slug: "other-receiving")
      expect(other).to be_valid
    end

    it "permite o mesmo formulário em recortes comprovadamente separados de cidade ou preço" do
      sale.update!(property_cities: ["Itapema"])
      other = build(:distribution_rule, tenant: tenant, source_meta: true, meta_forms: ["same-form"],
        business_type: :venda, property_cities: ["Porto Belo"])
      expect(other).to be_valid
      other.property_cities = ["itapema"]
      expect(other).not_to be_valid
      sale.update!(property_cities: [], max_price: 100)
      other.property_cities = []
      other.min_price = 101
      expect(other).to be_valid
      other.min_price = 100
      expect(other).not_to be_valid
    end

    it "não impede edição alheia ao recebimento em conflito legado" do
      other = create(:distribution_rule, tenant: tenant, source_meta: true, meta_forms: ["other-form"], business_type: :venda)
      other.update_columns(meta_forms: ["same-form"])
      other.reload.name = "Nome atualizado"
      expect(other).to be_valid
      other.business_type = :todos
      expect(other).not_to be_valid
    end

    it "não reinsere um formulário excluído em sincronizações futuras" do
      sale.update!(auto_add_forms: true, excluded_meta_form_ids: ["same-form"])
      sale.add_auto_meta_forms!(["same-form", "new-form"])
      expect(sale.reload.meta_forms).to eq(["new-form"])
      sale.update!(auto_add_forms: false)
      expect(sale.meta_form_excluded?("same-form")).to be(true)
    end
  end
end
