FactoryBot.define do
  factory :manual_checkin_request do
    admin_user
    store
    justification { "GPS falhou, estou fisicamente na loja com o encarregado #{Faker::Name.name}." }
    status { :pending }
  end
end
