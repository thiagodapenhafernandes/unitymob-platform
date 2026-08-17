FactoryBot.define do
  factory :task do
    tenant { lead&.tenant || Current.tenant || Tenant.default }
    lead
    admin_user { create(:admin_user, tenant: tenant) }
    title { "Retornar para o cliente" }
    kind { "follow_up" }
    status { "pendente" }
    priority { "normal" }
    due_at { 1.day.from_now }
  end
end
