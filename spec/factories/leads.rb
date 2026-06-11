FactoryBot.define do
  factory :lead do
    name { Faker::Name.name }
    phone { Faker::PhoneNumber.cell_phone }
    email { Faker::Internet.email }
    origin { "site" }
    status { :novo }
  end
end
