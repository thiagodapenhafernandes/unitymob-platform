require "rails_helper"

RSpec.describe WebhookSetting do
  it "preserva capturas por padrão e exige eventos válidos" do
    setting = described_class.new
    expect(setting.subscribed_events).to eq(described_class::DEFAULT_EVENTS)
    expect(setting.delivers_event?("qualified_lead")).to eq(false)
    setting.subscribed_events = ["", "unknown"]
    setting.valid?
    expect(setting.errors[:subscribed_events]).to be_present
  end

  it "rejeita formulários de outra conta" do
    tenant = Tenant.create!(name: "Conta #{SecureRandom.hex(3)}", slug: "conta-#{SecureRandom.hex(3)}")
    other = Tenant.create!(name: "Conta #{SecureRandom.hex(3)}", slug: "conta-#{SecureRandom.hex(3)}")
    form = PublicForm.ensure_default_announce_property!(tenant: other)
    setting = tenant.webhook_settings.new(public_form_ids: [form.id], form_delivery_scope: "forms")
    setting.valid?
    expect(setting.errors[:public_form_ids]).to be_present
  end
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
