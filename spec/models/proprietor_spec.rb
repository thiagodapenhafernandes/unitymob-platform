require "rails_helper"

RSpec.describe Proprietor, type: :model do
  describe "CPF/CNPJ uniqueness" do
    it "blocks a second manual proprietor with the same CPF/CNPJ" do
      create(:proprietor, cpf_cnpj: "123.456.789-00")

      duplicate = build(:proprietor, cpf_cnpj: "12345678900")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:cpf_cnpj]).to include("já cadastrado para outro proprietário")
    end

    it "allows blank CPF/CNPJ values" do
      create(:proprietor, cpf_cnpj: nil)

      expect(build(:proprietor, cpf_cnpj: "")).to be_valid
    end

    it "does not conflict with itself when updating" do
      proprietor = create(:proprietor, cpf_cnpj: "123.456.789-00")

      proprietor.name = "Nome atualizado"

      expect(proprietor).to be_valid
    end

    it "does not block Vista-managed records" do
      create(:proprietor, cpf_cnpj: "123.456.789-00")

      from_vista = build(:proprietor, cpf_cnpj: "123.456.789-00", vista_code: "C-9999")

      expect(from_vista).to be_valid
    end
  end
end
