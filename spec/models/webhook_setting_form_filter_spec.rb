require "rails_helper"

RSpec.describe WebhookSetting do
  it "entrega todos os formulários por padrão" do
    setting = described_class.new(form_delivery_scope: "all")

    expect(setting.delivers_form?("whatsapp_lead")).to be(true)
  end

  it "filtra por categoria do formulário público" do
    tenant = Tenant.create!(name: "Conta Webhook #{SecureRandom.hex(3)}", slug: "conta-webhook-#{SecureRandom.hex(3)}")
    form = PublicForm.ensure_default_announce_property!(tenant: tenant)
    setting = tenant.webhook_settings.new(
      webhook_url: "https://example.com/webhook",
      enabled: true,
      form_delivery_scope: "categories",
      form_categories: ["property_announcement"]
    )

    expect(setting.delivers_form?(form.webhook_origin, public_form: form)).to be(true)
    expect(setting.delivers_form?("contact_form")).to be(false)
  end

  it "filtra por formulário público específico" do
    tenant = Tenant.create!(name: "Conta Webhook Form #{SecureRandom.hex(3)}", slug: "conta-webhook-form-#{SecureRandom.hex(3)}")
    accepted = PublicForm.ensure_default_announce_property!(tenant: tenant)
    rejected = tenant.public_forms.create!(
      name: "Parceria",
      slug: "parceria",
      category: "partnership",
      title: "Parceria",
      submit_label: "Enviar",
      success_message: "Ok"
    )
    setting = tenant.webhook_settings.new(
      webhook_url: "https://example.com/webhook",
      enabled: true,
      form_delivery_scope: "forms",
      public_form_ids: [accepted.id]
    )

    expect(setting.delivers_form?(accepted.webhook_origin, public_form: accepted)).to be(true)
    expect(setting.delivers_form?(rejected.webhook_origin, public_form: rejected)).to be(false)
  end
end
