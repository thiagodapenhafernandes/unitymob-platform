require "rails_helper"

RSpec.describe EmailSetting do
  describe "#smtp_settings" do
    it "inclui timeouts explícitos para conexões SMTP" do
      setting = described_class.new(
        smtp_address: "smtp.example.com",
        smtp_port: 587,
        smtp_user_name: "user",
        smtp_password: "secret",
        from_email: "contato@example.com"
      )

      expect(setting.smtp_settings).to include(
        open_timeout: described_class::SMTP_OPEN_TIMEOUT,
        read_timeout: described_class::SMTP_READ_TIMEOUT
      )
    end
  end
end
