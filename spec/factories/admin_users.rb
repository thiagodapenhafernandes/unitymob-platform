FactoryBot.define do
  factory :admin_user do
    sequence(:email) { |n| "admin#{n}@salute.test" }
    password { "password123" }
    password_confirmation { "password123" }
    name { Faker::Name.name }
    role { :editor }
    acting_type { :both }
    field_agent_enabled { false }

    trait :admin do
      role { :admin }
    end

    trait :field_agent do
      field_agent_enabled { true }
    end
  end
end
