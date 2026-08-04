require "rails_helper"

RSpec.describe PublicForm do
  it "cria o formulário padrão de anuncie seu imóvel com campos essenciais" do
    tenant = Tenant.create!(name: "Conta Form #{SecureRandom.hex(3)}", slug: "conta-form-#{SecureRandom.hex(3)}")

    form = described_class.ensure_default_announce_property!(tenant: tenant)

    expect(form).to be_persisted
    expect(form.slug).to eq("anuncie-seu-imovel")
    expect(form.category).to eq("property_announcement")
    expect(form.fields.pluck(:name)).to include("name", "phone", "interest", "property_details")
    expect(form.fields.find_by!(name: "interest").normalized_options.map { |option| option["value"] }).to contain_exactly("venda", "locacao")
  end

  it "cria os formulários públicos padrão que entram no builder" do
    tenant = Tenant.create!(name: "Conta Defaults #{SecureRandom.hex(3)}", slug: "conta-defaults-#{SecureRandom.hex(3)}")

    forms = described_class.ensure_default_site_forms!(tenant: tenant)

    expect(forms.map(&:slug)).to contain_exactly("anuncie-seu-imovel", "corretor-parceiro", "trabalhe-conosco")
    expect(tenant.public_forms.find_by!(slug: "corretor-parceiro").category).to eq("partnership")
    expect(tenant.public_forms.find_by!(slug: "trabalhe-conosco").category).to eq("career")
  end

  it "bloqueia tipos de campo não permitidos" do
    tenant = Tenant.create!(name: "Conta Campo #{SecureRandom.hex(3)}", slug: "conta-campo-#{SecureRandom.hex(3)}")
    form = tenant.public_forms.create!(
      name: "Captação",
      slug: "captacao",
      category: "custom",
      title: "Captação",
      submit_label: "Enviar",
      success_message: "Ok"
    )

    field = form.fields.build(field_type: "script", name: "payload", label: "Payload")

    expect(field).not_to be_valid
    expect(field.errors[:field_type]).to be_present
  end
end
