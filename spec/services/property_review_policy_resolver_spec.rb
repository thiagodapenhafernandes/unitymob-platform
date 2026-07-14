require "rails_helper"

RSpec.describe PropertyReviewPolicyResolver do
  it "usa PropertySetting como fallback quando não há regra específica" do
    tenant = Tenant.default
    setting = PropertySetting.instance(tenant: tenant)
    setting.update!(required_broker_intake_checks: %w[proprietario fotos])

    result = described_class.call(
      tenant: tenant,
      property_setting: setting,
      registration_type: "terrenos",
      category: "Terreno",
      modality: "venda"
    )

    expect(result.source).to eq(:fallback)
    expect(result.required_checks).to eq(%w[proprietario fotos])
  end

  it "prioriza regra específica por tipo categoria e modalidade" do
    tenant = Tenant.default
    setting = PropertySetting.instance(tenant: tenant)
    create(
      :property_review_policy,
      tenant: tenant,
      property_setting: setting,
      registration_type: "terrenos",
      category: "Terreno",
      modality: "venda",
      required_broker_intake_checks: %w[proprietario area valor_negociacao]
    )

    result = described_class.call(
      tenant: tenant,
      property_setting: setting,
      registration_type: "terrenos",
      category: "Terreno",
      modality: "venda"
    )

    expect(result.source).to eq(:specific)
    expect(result.required_checks).to eq(%w[proprietario area valor_negociacao])
  end

  it "explica validações configuradas que não se aplicam ao conjunto" do
    tenant = Tenant.default
    setting = PropertySetting.instance(tenant: tenant)
    setting.update!(required_broker_intake_checks: %w[proprietario garantia_locaticia infraestrutura vagas])

    result = described_class.call(
      tenant: tenant,
      property_setting: setting,
      registration_type: "terrenos",
      category: "Terreno",
      modality: "venda"
    )

    expect(result.applicable_checks).to include(["proprietario", "Dados do proprietário"])
    expect(result.ignored_checks.map(&:key)).to include("garantia_locaticia", "infraestrutura", "vagas")
  end
end
