FactoryBot.define do
  factory :admin_user do
    tenant { super_admin ? nil : (profile&.tenant || Current.tenant || Tenant.default) }
    sequence(:email) { |n| "admin#{n}-#{SecureRandom.hex(4)}@salute.test" }
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

    after(:build) do |admin_user|
      if admin_user.super_admin?
        admin_user.tenant = nil
        admin_user.profile = nil
        admin_user.horizontal_profile = nil
        admin_user.manager = nil
        next
      end

      admin_user.tenant ||= Current.tenant || Tenant.default
      admin_user.profile ||= if admin_user.role == "admin"
        admin_user.tenant.profiles.find_or_create_by!(key: "tenant_owner") do |profile|
          profile.name = "Tenant Owner"
          profile.axis = "vertical"
          profile.permissions = { "admin" => true }
        end
      else
        admin_user.tenant.profiles.find_or_create_by!(key: "agent") do |profile|
          profile.name = "Agent"
          profile.axis = "vertical"
          profile.permissions = Profile.default_permissions_for("Corretor")
        end
      end
    end
  end
end
