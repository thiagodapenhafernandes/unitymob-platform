FactoryBot.define do
  factory :location_ping do
    check_in
    admin_user { check_in.admin_user }
    latitude { -26.9906 }
    longitude { -48.6348 }
    accuracy_meters { 10 }
    inside_radius { true }
    recorded_at { Time.current }
  end
end
