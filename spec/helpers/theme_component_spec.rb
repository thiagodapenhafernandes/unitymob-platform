require "rails_helper"

RSpec.describe ApplicationHelper, "#theme_component" do
  def stub_theme(key)
    tenant = instance_double(Tenant, public_site_theme_key: key)
    helper.define_singleton_method(:public_tenant) { tenant }
  end

  it "resolve os componentes luxury com a variante do tema" do
    stub_theme("salute_luxury")

    expect(helper.theme_component_path(:property_card)).to eq("public_theme/components/property_card")
    expect(helper.theme_variant).to eq("salute-luxury")
  end

  it "resolve os componentes default com a variante default" do
    stub_theme("default")

    expect(helper.theme_component_path(:property_card)).to eq("shared/tailwind/property_card")
    expect(helper.theme_component_path(:property_grid)).to eq("public_theme/components/default_property_grid")
    expect(helper.theme_variant).to eq("default")
  end

  it "cai para o default em tema desconhecido" do
    stub_theme("tema_que_nao_existe")

    expect(helper.theme_component_path(:hero)).to eq("hero")
    expect(helper.theme_variant).to eq("default")
  end

  it "cai para o default sem tenant" do
    helper.define_singleton_method(:public_tenant) { nil }

    expect(helper.theme_component_path(:shell)).to eq("layouts/default_shell")
  end
end
