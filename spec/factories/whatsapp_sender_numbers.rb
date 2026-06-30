FactoryBot.define do
  factory :whatsapp_sender_number do
    tenant { whatsapp_business_integration&.tenant || Current.tenant || Tenant.default }
    label { "Vendas principal" }
    display_phone_number { "5511999990000" }
    phone_number_id { "123456789012345" }
    waba_id { "616242481017427" }
    status { "connected" }
    active { true }
    association :whatsapp_business_integration
  end
end
