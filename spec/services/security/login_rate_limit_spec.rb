require "rails_helper"

RSpec.describe Security::LoginRateLimit do
  it "limpa os contadores do e-mail e dos IPs recentes" do
    user = create(:admin_user, email: "Pessoa@Salute.Test")
    recent_ip = "203.0.113.15"
    AccessAuditLog.log!(
      event_type: "login",
      result: "denied",
      request: instance_double(
        ActionDispatch::Request,
        user_agent: "RSpec",
        remote_ip: recent_ip,
        fullpath: "/admin/sign_in",
        request_method: "POST",
        params: {}
      ),
      admin_user: user,
      reason: "Senha inválida"
    )

    expect(Rack::Attack.cache).to receive(:reset_count)
      .with("admin/login/email:pessoa@salute.test", 20.minutes.to_i)
    expect(Rack::Attack.cache).to receive(:reset_count)
      .with("admin/login/ip:#{recent_ip}", 5.minutes.to_i)

    result = described_class.reset!(admin_user: user)

    expect(result.ips).to eq([recent_ip])
  end
end
