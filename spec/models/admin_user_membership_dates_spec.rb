require "rails_helper"

RSpec.describe AdminUser, "datas de vínculo" do
  let(:user) { create(:admin_user) }

  it "aceita datas opcionais, saída isolada e saída no dia da entrada" do
    expect(user.update(source_created_on: nil, source_departed_on: nil)).to be(true)
    expect(user.update(source_departed_on: "2025-10-01")).to be(true)
    expect(user.update(source_created_on: "2025-10-01")).to be(true)
  end

  it "recusa uma saída anterior à entrada, sem mudar o status" do
    expect(user.update(source_created_on: "2025-10-02", source_departed_on: "2025-10-01")).to be(false)
    expect(user.errors.full_messages).to include("Data de saída não pode ser anterior à data de entrada")
    expect(user.reload.active?).to be(true)
  end

  it "recusa data inválida em vez de apagar silenciosamente o histórico" do
    user.update!(source_created_on: "2025-01-01")
    expect(user.update(source_created_on: "2025-02-31")).to be(false)
    expect(user.reload.source_created_on).to eq(Date.new(2025, 1, 1))
  end

  it "não impede outras edições de um histórico legado inconsistente" do
    user.update_columns(source_created_on: Date.new(2025, 2, 1), source_departed_on: Date.new(2025, 1, 1))
    expect(user.reload.update(name: "Nome corrigido")).to be(true)
  end

  it "não inventa datas ao criar ou alterar o status ativo" do
    user.update!(active: false)
    expect(user.reload.attributes.values_at("source_created_on", "source_departed_on")).to eq([nil, nil])
    user.update!(active: true, source_created_on: "2020-01-01", source_departed_on: "2021-02-01")
    expect(user.reload).to be_active
  end
end
