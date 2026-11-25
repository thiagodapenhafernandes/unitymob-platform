require "rails_helper"

RSpec.describe Habitations::InternalDataAccess do
  let(:tenant) { Tenant.default }
  let(:profile) { tenant.profiles.create!(name: "Consulta #{SecureRandom.hex(4)}", axis: "vertical", position: 7319, permissions: { "imoveis" => { "view" => true, "scope" => "team", "internal_data_scope" => "team" } }) }
  let(:user) { create(:admin_user, tenant: tenant, profile: profile, acting_type: :sales) }
  let(:subordinate) { create(:admin_user, tenant: tenant, rentals_manager: user, acting_type: :rentals) }
  let(:outsider) { create(:admin_user, tenant: tenant) }
  let(:access) { described_class.new(user) }

  def set_scope(value)
    profile.update!(permissions: profile.permissions.deep_merge("imoveis" => { "internal_data_scope" => value }))
    user.reload
    described_class.new(user)
  end

  it "mantém o legado quando a configuração está ausente" do
    expect(set_scope(nil)).not_to be_configured
  end

  it "limita próprios ao usuário e aos seus vínculos, sem incluir subordinados" do
    own = create(:habitation, admin_user: user)
    team = create(:habitation, admin_user: subordinate)
    assigned = create(:habitation, admin_user: outsider)
    assigned.broker_assignments.create!(admin_user: user, role: :captador)
    access = set_scope("own")
    expect(access.allowed?(own)).to be(true)
    expect(access.allowed?(assigned)).to be(true)
    expect(access.allowed?(team)).to be(false)
  end

  it "inclui a equipe mesmo em locação e rejeita outros corretores" do
    team = create(:habitation, admin_user: subordinate, status: "Aluguel")
    outside = create(:habitation, admin_user: outsider)
    expect(access.allowed?(team)).to be(true)
    expect(access.allowed?(outside)).to be(false)
  end

  it "todos libera a conta, sem atravessar tenants" do
    other = Tenant.create!(name: "Outra", slug: "outra-#{SecureRandom.hex(5)}")
    outside = create(:habitation, admin_user: outsider)
    foreign = create(:habitation, tenant: other)
    access = set_scope("all")
    expect(access.allowed?(outside)).to be(true)
    expect(access.allowed?(foreign)).to be(false)
  end

  it "usa a configuração horizontal quando o vertical ainda mantém a regra atual" do
    set_scope(nil)
    horizontal = tenant.profiles.create!(name: "Consulta horizontal #{SecureRandom.hex(4)}", axis: "horizontal", vertical_profile: profile, permissions: { "imoveis" => { "view" => true, "internal_data_scope" => "all" } })
    user.update!(horizontal_profile: horizontal)
    expect(described_class.new(user).allowed?(create(:habitation, admin_user: outsider))).to be(true)
  end

  it "mantém a restrição horizontal e não concede acesso à tela de imóveis" do
    horizontal = tenant.profiles.create!(name: "Restrição #{SecureRandom.hex(4)}", axis: "horizontal", vertical_profile: profile, permissions: { "imoveis" => { "view" => true, "internal_data_scope" => "own" } })
    user.update!(horizontal_profile: horizontal)
    set_scope("all")
    expect(described_class.new(user).allowed?(create(:habitation, admin_user: subordinate))).to be(false)
    horizontal.update!(permissions: { "imoveis" => { "view" => false, "internal_data_scope" => "all" } })
    user.reload
    expect(described_class.new(user).allowed?(create(:habitation, admin_user: user))).to be(false)
  end
end
