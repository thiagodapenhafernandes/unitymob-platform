require "rails_helper"

RSpec.describe Profile, "papel estável por key (rename-safe)", type: :model do
  it "atribui o key canônico ao criar um perfil de sistema pelo nome" do
    expect(Profile.create!(name: "Administrador").key).to eq("administrador")
    expect(Profile.create!(name: "Gerente").key).to eq("gerente")
    expect(Profile.create!(name: "Administrativo").key).to eq("administrativo")
    expect(Profile.create!(name: "Diretor").key).to eq("diretor")
    expect(Profile.create!(name: "Corretor").key).to eq("corretor")
  end

  it "não atribui key a perfis customizados" do
    expect(Profile.create!(name: "Supervisor Regional").key).to be_nil
  end

  it "predicados de papel seguem o key, não o nome" do
    admin = Profile.create!(name: "Administrador")
    adm   = Profile.create!(name: "Administrativo")

    expect(admin.admin?).to be(true)
    expect(adm.administrativo?).to be(true)
    expect(adm.admin?).to be(false)
  end

  it "RENOMEAR um perfil de sistema preserva o comportamento (key não muda)" do
    profile = Profile.create!(name: "Administrativo")
    profile.update!(name: "Equipe Interna")

    expect(profile.reload.key).to eq("administrativo")
    expect(profile.administrativo?).to be(true)
    expect(profile.name).to eq("Equipe Interna")
  end

  it "admin? também vale pela flag de permissão, sem key" do
    custom = Profile.create!(name: "Super", permissions: { "admin" => true })
    expect(custom.key).to be_nil
    expect(custom.admin?).to be(true)
  end

  it "não duplica key quando o nome canônico já está em uso por outro perfil" do
    Profile.create!(name: "Gerente") # ocupa key "gerente"
    # renomeia o canônico original e tenta criar outro "Gerente"
    other = Profile.create!(name: "Gerente Comercial")
    expect(other.key).to be_nil
  end
end
