FactoryBot.define do
  factory :user_meta_integration do
    association :admin_user
    access_token { "meta-token" }
    facebook_user_id { "facebook-user-1" }
    name { "Meta User" }
    email { "meta@example.com" }
  end

  factory :meta_facebook_page do
    association :user_meta_integration
    sequence(:page_id) { |n| "page-#{n}" }
    sequence(:name) { |n| "Página #{n}" }
    access_token { "page-token" }
    active { true }
    category { "Imobiliária" }
  end

  factory :meta_lead_form do
    association :meta_facebook_page
    sequence(:form_id) { |n| "form-#{n}" }
    sequence(:name) { |n| "Formulário #{n}" }
    active { true }
    facebook_created_at { Time.current }
  end
end
