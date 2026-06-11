FactoryBot.define do
  factory :trusted_device do
    association :admin_user
    sequence(:fingerprint) { |n| "device-#{n}" }
    status { "pending" }
    device_type { "Computador" }
    browser { "Chrome" }
    platform { "macOS" }
    last_ip { "127.0.0.1" }
    last_seen_at { Time.current }
  end
end
