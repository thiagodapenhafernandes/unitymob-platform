class Current < ActiveSupport::CurrentAttributes
  attribute :admin_user, :tenant, :request_ip, :request_user_agent, :request_metadata
end
