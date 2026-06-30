FactoryBot.define do
  factory :store do
    tenant { Current.tenant || Tenant.default }
    sequence(:name) { |n| "Loja #{n}" }
    address { "Av. Atlântica, 3750" }
    city { "Balneário Camboriú" }
    state { "SC" }
    latitude { -26.9906 }
    longitude { -48.6348 }
    geofence_radius_meters { 150 }
    out_of_radius_tolerance_minutes { 10 }
    auto_checkout_after_minutes { 60 }
    timezone { "America/Sao_Paulo" }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :without_location do
      latitude { nil }
      longitude { nil }
    end

    trait :small_radius do
      geofence_radius_meters { 25 }
    end
  end
end
