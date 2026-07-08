require "rails_helper"

RSpec.describe NotificationTemplateSetting, type: :model do
  let(:tenant) { Tenant.default }

  before do
    NotificationTemplateSetting.where(tenant_id: tenant.id).delete_all
  end

  def build_template(name:, body:)
    tenant.whatsapp_templates.create!(
      name: name,
      language: "pt_BR",
      category: "UTILITY",
      body: body,
      status: "APPROVED",
      template_type: "text",
      header_format: "none"
    )
  end

  it "salva o mapa padrao de variaveis para distribuicao de leads" do
    template = build_template(name: "lead_distribution_default", body: "Lead {{1}} veio de {{2}}")

    setting = tenant.notification_template_settings.create!(
      purpose: "lead_distribution_broker",
      whatsapp_template: template
    )

    expect(setting.variable_mapping["1"]).to eq("lead_name")
    expect(setting.variable_mapping["2"]).to eq("lead_origin")
  end

  it "aceita mapear dinamicamente a quantidade de variaveis do template" do
    template = build_template(name: "lead_distribution_short", body: "Lead {{1}} para {{2}}")

    setting = tenant.notification_template_settings.new(
      purpose: "lead_distribution_broker",
      whatsapp_template: template,
      variable_mapping: {
        "1" => "lead_name",
        "2" => "broker_name"
      }
    )

    expect(setting).to be_valid
  end
end
