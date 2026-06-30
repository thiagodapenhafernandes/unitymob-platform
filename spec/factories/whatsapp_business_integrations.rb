FactoryBot.define do
  factory :whatsapp_business_integration do
    tenant { connected_by_admin_user&.tenant || Current.tenant || Tenant.default }
    status { "connected" }
    waba_id { "616242481017427" }
    phone_number_id { "649374078254590" }
    business_id { "1234567890" }
    access_token { "EAATESTTOKEN123456" }
    connected_at { Time.current }
    default_whatsapp_number { "554733111067" }
    sale_whatsapp_number { "5547991111111" }
    rent_whatsapp_number { "5547992222222" }
    sale_rent_whatsapp_number { "5547993333333" }
    association :connected_by_admin_user, factory: :admin_user
  end
end
