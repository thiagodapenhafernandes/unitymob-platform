require "rails_helper"

RSpec.describe Captacao, type: :model do
  describe "validações da etapa de características" do
    it "exige área privativa para imóvel não-terreno" do
      captacao = build(:captacao, property_kind: :residencial, area_total: 120, area_privativa: nil)

      expect(captacao).not_to be_valid(:caracteristicas)
      expect(captacao.errors[:area_privativa]).to be_present
      expect(captacao.errors[:area_total]).to be_blank
    end

    it "mantém área total obrigatória para terreno" do
      captacao = build(:captacao, property_kind: :terreno, area_total: nil, area_privativa: nil)

      expect(captacao).not_to be_valid(:caracteristicas)
      expect(captacao.errors[:area_total]).to be_present
      expect(captacao.errors[:area_privativa]).to be_blank
    end
  end
end
