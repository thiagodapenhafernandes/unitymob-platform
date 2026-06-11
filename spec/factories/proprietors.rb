FactoryBot.define do
  factory :proprietor do
    sequence(:name) { |n| "Proprietário #{n}" }
    role { "owner" }
    sequence(:email) { |n| "proprietario#{n}@salute.test" }
    phone_primary { "(47) 99999-0000" }
    city { "Balneário Camboriú" }
  end
end
