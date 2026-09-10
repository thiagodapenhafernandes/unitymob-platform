require "rails_helper"

RSpec.describe "Salute: cadastro e publicação", type: :model do
  it "gera URL com código automático e mantém o endereço antigo ao corrigir um legado" do
    habitation = create(:habitation, codigo: nil, categoria: "Apartamento")
    expect(habitation.slug).to end_with("-#{habitation.codigo}")
    legacy = "apartamento-#{SecureRandom.uuid}"
    habitation.update_column(:slug, legacy)
    habitation.update!(titulo_anuncio: "Apartamento revisado")
    expect(habitation.slug).to end_with("-#{habitation.codigo}")
    expect(habitation.tenant.habitations.friendly.find(legacy)).to eq(habitation)
  end

  it "não apresenta permuta como característica de infraestrutura" do
    habitation = build(:habitation, aceita_permuta_flag: false, aceita_permuta_answer: "nao", caracteristica_unica: ["Aceita Permuta", "Vista mar"], infra_estrutura: ["Aceita Permuta", "Piscina"])
    expect(habitation.unique_features).to eq(["Vista mar"])
    expect(habitation.leisure_features_for_display).to eq(["Piscina"])
  end

  it "distingue características de galpão, sala comercial e terreno" do
    warehouse = build(:habitation, categoria: "Galpão", registration_profile: "comerciais_industriais")
    office = build(:habitation, categoria: "Sala Comercial", registration_profile: "comerciais_industriais")
    land = build(:habitation, categoria: "Terreno", registration_profile: "terrenos")
    expect(warehouse.standard_feature_options).not_to eq(office.standard_feature_options)
    expect(land.standard_feature_options).not_to eq(office.standard_feature_options)
  end

  it "respeita a restrição de proprietários da função horizontal vinculada ao administrador" do
    tenant = Tenant.default
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    horizontal = Profile.create!(tenant: tenant, name: "Interno #{SecureRandom.hex(4)}", axis: "horizontal", vertical_profile: owner_profile, permissions: { "proprietarios" => { "view" => false, "manage" => false } })
    user = build(:admin_user, tenant: tenant, profile: owner_profile, horizontal_profile: horizontal)
    owner = build(:admin_user, tenant: tenant, profile: owner_profile)
    expect(user.can?(:view, :proprietarios)).to be(false)
    expect(user.can?(:manage, :proprietarios)).to be(false)
    expect(owner.can?(:manage, :proprietarios)).to be(true)
  end

  it "recusa resposta Vista sem cadastro em vez de criar um imóvel vazio" do
    Current.set(tenant: Tenant.default) do
      response = instance_double(HTTParty::Response, code: 200, body: { Foto: [] }.to_json)
      allow(HTTParty).to receive(:get).and_return(response)
      service = SyncPropertyService.new("INCOMPLETE-#{SecureRandom.hex(4)}", host: "https://vista.test", token: "test")
      expect { expect(service.perform).to include(success: false, error: /incompleta/) }.not_to change(Habitation, :count)
    end
  end
  it "importa o telefone principal do Vista mesmo sem celular e não apaga contatos com false" do
    Current.set(tenant: Tenant.default) do
      service = SyncPropertyService.new("OWNER")
      owner = service.send(:resolve_proprietor, { "Proprietario" => "Owner #{SecureRandom.hex(4)}", "CodigoProprietario" => "OWNER-#{SecureRandom.hex(4)}" }, { "FonePrincipal" => "(55) 99999-1234", "EmailResidencial" => "owner@example.test", "Celular" => false })
      expect(owner.phone_primary).to be_present
      expect(owner.email).to eq("owner@example.test")
      expect(owner.mobile_phone).not_to eq("false")
    end
  end

  it "preserva contato legado do mesmo proprietário, mas não o transfere a outro proprietário" do
    owner = Tenant.default.proprietors.create!(name: "Owner #{SecureRandom.hex(4)}")
    habitation = create(:habitation, proprietor: owner, proprietario_celular: "(55) 99999-1234")
    Habitations::ProprietorLinker.new(habitation).call
    expect(habitation.proprietario_celular).to be_present
    other = Tenant.default.proprietors.create!(name: "Other #{SecureRandom.hex(4)}")
    habitation.proprietor_id = other.id
    Habitations::ProprietorLinker.new(habitation).call
    expect(habitation.proprietario_celular).to be_blank
  end

  it "não reativa permuta desmarcada ao editar outras características" do
    habitation = create(:habitation, aceita_permuta_answer: "nao", aceita_permuta_flag: false, caracteristicas: ["Aceita Permuta"])
    habitation.update!(caracteristicas: ["Aceita Permuta", "Sacada"])
    expect(habitation.reload.aceita_permuta_flag).to be(false)
  end

end
