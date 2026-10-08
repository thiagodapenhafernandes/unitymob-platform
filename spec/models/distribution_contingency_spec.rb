require "rails_helper"

RSpec.describe "Configuração de contingência" do
  let(:tenant) { Tenant.create!(name: "Contingência", slug: "config-contingency-#{SecureRandom.hex(4)}") }
  let(:target) { create(:distribution_rule, tenant: tenant) }
  let(:rule) { create(:distribution_rule, tenant: tenant) }
  around { |example| Current.set(tenant: tenant) { example.run } }

  def configure(destination = target)
    rule.assign_attributes(contingency_enabled: true, contingency_rule: destination, contingency_triggers: ["unavailable"])
  end

  it "aceita outra regra terminal ativa da conta" do
    configure
    expect(rule).to be_valid
  end

  it "exige destino e situações quando ativada" do
    rule.assign_attributes(contingency_enabled: true, contingency_triggers: [])
    expect(rule).not_to be_valid
    expect(rule.errors.attribute_names).to include(:contingency_rule, :contingency_triggers)
  end

  it "rejeita a própria regra" do
    configure(rule)
    expect(rule).not_to be_valid
  end

  it "rejeita destino de outra conta" do
    configure(create(:distribution_rule, tenant: Tenant.create!(name: "Outra", slug: "other-#{SecureRandom.hex(4)}")))
    expect(rule).not_to be_valid
  end

  it "rejeita destino inativo" do
    target.update!(active: false)
    configure
    expect(rule).not_to be_valid
  end

  it "rejeita destino que depende de escolha manual" do
    target.update!(distribution_mode: :attendance)
    configure
    expect(rule).not_to be_valid
  end

  it "impede encadear o destino em outra regra" do
    configure
    rule.save!
    target.assign_attributes(contingency_enabled: true, contingency_rule: create(:distribution_rule, tenant: tenant), contingency_triggers: ["unavailable"])
    expect(target).not_to be_valid
  end

  it "impede ativar encaminhamento no destino padrão da conta" do
    LeadSetting.instance(tenant: tenant).update!(default_distribution_rule: target)
    target.assign_attributes(contingency_enabled: true, contingency_rule: rule, contingency_triggers: ["unavailable"])
    expect(target).not_to be_valid
  end

  it "valida prazos e motivos" do
    configure
    rule.assign_attributes(contingency_pool_minutes: 0, contingency_unavailable_minutes: -1, contingency_triggers: ["inventado"])
    expect(rule).not_to be_valid
  end

  it "impede selecionar regra com encaminhamento como padrão" do
    configure
    rule.save!
    setting = LeadSetting.instance(tenant: tenant)
    setting.default_distribution_rule = rule
    expect(setting).not_to be_valid
  end

  it "permite alterar outras configurações quando o destino padrão foi desativado depois" do
    setting = LeadSetting.instance(tenant: tenant)
    setting.update!(default_distribution_rule: target)
    target.update!(active: false)
    expect(setting.update(vcard_enabled: !setting.vcard_enabled?)).to eq(true)
  end
end
