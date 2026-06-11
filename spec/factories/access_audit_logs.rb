FactoryBot.define do
  factory :access_audit_log do
    admin_user
    event_type { "login" }
    result { "allowed" }
    reason { "Credenciais válidas" }
    email { admin_user&.email }
    ip { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15" }
    device_type { "Computador" }
    browser { "Safari" }
    platform { "macOS" }
    path { "/admin/sign_in" }
    request_method { "POST" }
    controller_name { "admin/sessions" }
    action_name { "create" }
    metadata { {} }
    created_at { Time.current }
  end
end
