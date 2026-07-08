FactoryBot.define do
  factory :whatsapp_sender_number do
    tenant { whatsapp_business_integration&.tenant || Current.tenant || Tenant.default }
    label { "Vendas principal" }
    sequence(:display_phone_number) { |n| "551199999#{n.to_s.rjust(4, '0')}" }
    sequence(:phone_number_id) { |n| "123456789#{n.to_s.rjust(6, '0')}" }
    waba_id { "616242481017427" }
    status { "connected" }
    active { true }
    use_for_notifications { false }
    association :whatsapp_business_integration
  end
end
