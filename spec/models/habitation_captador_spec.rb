require "rails_helper"

RSpec.describe Habitation, type: :model do
  describe "#primary_captador" do
    it "prioriza o captador definido nos responsáveis e agenciamento" do
      principal = create(:admin_user, name: "Captador Principal")
      vinculado = create(:admin_user, name: "Captador do Agenciamento")
      habitation = create(:habitation, admin_user: principal)
      habitation.broker_assignments.create!(admin_user: vinculado, role: "captador")

      expect(habitation.primary_captador).to eq(vinculado)
      expect(habitation.primary_captador_name).to eq("Captador do Agenciamento")
      expect(habitation.captador_names).to eq(["Captador do Agenciamento", "Captador Principal"])
    end

    it "usa o captador principal antigo quando não há vínculo de captação" do
      principal = create(:admin_user, name: "Captador Principal")
      habitation = create(:habitation, admin_user: principal)

      expect(habitation.primary_captador).to eq(principal)
      expect(habitation.primary_captador_name).to eq("Captador Principal")
      expect(habitation.captador_names).to eq(["Captador Principal"])
    end

    it "usa o nome importado do Vista quando não há usuário vinculado" do
      habitation = build(:habitation, admin_user: nil, corretor_nome: "Corretor Vista")

      expect(habitation.primary_captador).to be_nil
      expect(habitation.primary_captador_name).to eq("Corretor Vista")
      expect(habitation.captador_names).to eq(["Corretor Vista"])
    end

    it "usa o usuário fake da DWV para imóveis DWV sem captador direto" do
      dwv_user = create(:admin_user, name: "Dwv - Imóveis Pauta", email: "laudicardoso@gmail.com")
      habitation = build(:habitation, tenant: dwv_user.tenant, admin_user: nil, imovel_dwv: "Sim")

      expect(habitation.primary_captador).to eq(dwv_user)
      expect(habitation.primary_captador_name).to eq("Dwv - Imóveis Pauta")
      expect(habitation.captador_names).to eq(["Dwv - Imóveis Pauta"])
    end

    it "remove nomes duplicados do resumo de captadores" do
      principal = create(:admin_user, name: "Captador Principal")
      habitation = create(:habitation, admin_user: principal, corretor_nome: "Captador Principal")
      habitation.broker_assignments.create!(admin_user: principal, role: "captador")

      expect(habitation.captador_names).to eq(["Captador Principal"])
    end
  end
end
