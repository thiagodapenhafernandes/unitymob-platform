FactoryBot.define do
  factory :check_in do
    admin_user
    store
    store_shift
    checked_in_at { Time.current }
    status { :active }
    checkin_latitude { -26.9906 }
    checkin_longitude { -48.6348 }
    checkin_accuracy_meters { 10 }
  end
end
