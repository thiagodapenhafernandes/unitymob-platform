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

    it "permite registrar tentativa sem usuário autenticado fora de Tenant" do
      request = instance_double(
        ActionDispatch::Request,
        user_agent: "Mozilla/5.0",
        remote_ip: "189.1.2.3",
        fullpath: "/admin/sign_in",
        request_method: "POST",
        params: { controller: "admin/sessions", action: "create" }
      )

      log = described_class.log!(event_type: "login", result: "denied", request: request, email: "nao-encontrado@example.test")

      expect(log).to be_persisted
      expect(log.tenant_id).to be_nil
      expect(log.actor_name).to eq("nao-encontrado@example.test")
    end

    it "permite registrar acesso de Admin do Sistema fora de Tenant" do
      request = instance_double(
        ActionDispatch::Request,
        user_agent: "Mozilla/5.0",
        remote_ip: "189.1.2.3",
        fullpath: "/admin/system",
        request_method: "GET",
        params: { controller: "admin/system", action: "index" }
      )
      system_admin = create(:admin_user, super_admin: true, name: "Admin Plataforma")

      log = described_class.log!(event_type: "admin_access", result: "allowed", request: request, admin_user: system_admin)

      expect(log).to be_persisted
      expect(log.tenant_id).to be_nil
      expect(log.actor_name).to eq("Admin Plataforma")
    end
  end

  it "mantém tenant obrigatório e consistente para usuário de conta" do
    admin = create(:admin_user)
    other_tenant = Tenant.create!(name: "Outro audit #{SecureRandom.hex(3)}", slug: "outro-audit-#{SecureRandom.hex(3)}")

    expect(build(:access_audit_log, admin_user: admin, tenant: other_tenant)).not_to be_valid
    expect(build(:access_audit_log, admin_user: admin, tenant: admin.tenant)).to be_valid
  end

  it "não usa nome de admin_user de outro Tenant no actor_name" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: profile, name: "Usuário Externo")
    log = build(:access_audit_log, tenant: tenant, admin_user_id: other_user.id, email: nil)

    expect(log.actor_name).to eq("Usuário não identificado")
  end
end
