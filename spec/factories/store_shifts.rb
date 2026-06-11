FactoryBot.define do
  factory :store_shift do
    store
    admin_user
    day_of_week { 1 } # segunda
    start_time { "09:00" }
    end_time { "18:00" }
    active { true }
  end
end
