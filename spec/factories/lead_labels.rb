FactoryBot.define do
  factory :lead_label do
    tenant { Current.tenant || Tenant.default }
    admin_user
    sequence(:name) { |n| "Etiqueta #{n}" }
    color { "blue" }
  end
end
