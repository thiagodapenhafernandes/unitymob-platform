FactoryBot.define do
  factory :whatsapp_campaign_unsubscribe do
    association :whatsapp_sender_number
    phone_number { "5511999990000" }
    contact_name { "Contato Descadastrado" }
    source { "campaign_button" }
    reason { "Descadastro solicitado pelo contato." }
    unsubscribed_at { Time.current }
    metadata { {} }
  end
end
