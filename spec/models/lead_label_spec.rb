require "rails_helper"

RSpec.describe LeadLabel, type: :model do
  let(:admin) { create(:admin_user, :admin) }

  describe "validations" do
    it "exige nome e cor válida" do
      label = LeadLabel.new(admin_user: admin, tenant: admin.tenant, name: "", color: "rosa")
      expect(label).not_to be_valid
      expect(label.errors[:name]).to be_present
      expect(label.errors[:color]).to be_present
    end

    it "impede nomes duplicados (case-insensitive) do mesmo usuário" do
      create(:lead_label, admin_user: admin, name: "Quente")
      dup = build(:lead_label, admin_user: admin, name: "quente")
      expect(dup).not_to be_valid
    end

    it "permite o mesmo nome para usuários diferentes (etiquetas são privadas)" do
      other = create(:admin_user, :admin)
      create(:lead_label, admin_user: admin, name: "Quente")
      expect(build(:lead_label, admin_user: other, name: "Quente")).to be_valid
    end
  end

  describe ".ensure_defaults_for" do
    it "semeia as 5 etiquetas padrão no primeiro uso" do
      expect { LeadLabel.ensure_defaults_for(admin) }.to change { admin.lead_labels.count }.from(0).to(5)
      expect(admin.lead_labels.ordered.pluck(:name)).to eq(%w[Quente Morno Frio Investidor VIP])
    end

    it "é idempotente e não sobrescreve customizações" do
      LeadLabel.ensure_defaults_for(admin)
      admin.lead_labels.ordered.first.update!(name: "Muito quente")
      expect { LeadLabel.ensure_defaults_for(admin) }.not_to change { admin.lead_labels.count }
      expect(admin.lead_labels.ordered.first.name).to eq("Muito quente")
    end
  end

  describe "atribuição de posição" do
    it "incrementa a posição na criação" do
      a = create(:lead_label, admin_user: admin, name: "A")
      b = create(:lead_label, admin_user: admin, name: "B")
      expect(b.position).to be > a.position
    end
  end
end
