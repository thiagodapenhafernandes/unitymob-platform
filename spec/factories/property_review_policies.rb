FactoryBot.define do
  factory :property_review_policy do
    tenant { Current.tenant || Tenant.default }
    property_setting { PropertySetting.instance(tenant: tenant) }
    registration_type { "terrenos" }
    category { "Terreno" }
    modality { "venda" }
    broker_capture_layer_enabled { true }
    required_broker_intake_checks { PropertySetting.default_broker_capture_checks }
    returnable_intake_edit_sections { PropertySetting.default_returnable_sections }
    notify_internal_review_events { true }
    notify_email_review_events { false }
  end
end
