require "rails_helper"

RSpec.describe AccessAuditLog, type: :model do
  describe ".log!" do
    it "records device metadata from the user agent" do
      request = instance_double(
        ActionDispatch::Request,
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1",
        remote_ip: "189.1.2.3",
        fullpath: "/admin/sign_in",
        request_method: "POST",
        params: { controller: "admin/sessions", action: "create" }
      )

      log = described_class.log!(event_type: "login", result: "allowed", request: request, email: "corretor@salute.test")

      expect(log).to have_attributes(
        device_type: "Celular",
        browser: "Safari",
        platform: "iOS"
      )
      expect(log.ip.to_s).to eq("189.1.2.3")
    end
  end
end
