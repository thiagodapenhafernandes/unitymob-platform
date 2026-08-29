FactoryBot.define do
  factory :appointment do
    tenant { lead&.tenant || habitation&.tenant || Current.tenant || Tenant.default }
    lead
    admin_user { create(:admin_user, tenant: tenant) }
    title { "Visita agendada" }
    kind { "visita" }
    status { "agendado" }
    starts_at { 1.day.from_now }
  end
end
