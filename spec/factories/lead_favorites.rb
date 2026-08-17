FactoryBot.define do
  factory :lead_favorite do
    tenant { Current.tenant || Tenant.default }
    admin_user { association(:admin_user, tenant: tenant) }
    lead { association(:lead, tenant: tenant, admin_user: admin_user) }
  end
end
