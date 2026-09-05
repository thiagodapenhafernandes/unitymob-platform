# A confiança é provisionada uma vez por servidor; contas nunca recebem configuração manual.
class Support::Registration
  def self.enabled?
    !SupportDesk.central? && ENV['SUPPORT_INSTANCE_ID'].present? && ENV['SUPPORT_INSTANCE_SECRET'].to_s.length >= 32
  end

  def self.uid(instance, tenant_id) = "#{instance}:#{tenant_id}"
  def self.secret(key, uid) = OpenSSL::HMAC.hexdigest('SHA256', key, "support-account:#{uid}")

  def self.local_account(tenant)
    existing = Support::Account.find_by(local_tenant_id: tenant.id)
    return existing if existing || !enabled?
    tenant.with_lock do
      Support::Account.find_by(local_tenant_id: tenant.id) || Support::Account.create!(
        local_tenant_id: tenant.id, uid: uid(ENV.fetch('SUPPORT_INSTANCE_ID'), tenant.id), name: tenant.name,
        endpoint: ENV.fetch('SUPPORT_CENTRAL_URL', 'https://admin.unitymob.com.br'),
        secret: secret(ENV.fetch('SUPPORT_INSTANCE_SECRET'), uid(ENV.fetch('SUPPORT_INSTANCE_ID'), tenant.id)))
    end
  end

  def self.sync(tenant)
    account = local_account(tenant)
    # Contas vinculadas anteriormente mantêm sua identidade e histórico.
    return unless account.uid == uid(ENV.fetch('SUPPORT_INSTANCE_ID'), tenant.id)
    connection = Support::Account.new(uid: ENV.fetch('SUPPORT_INSTANCE_ID'), secret: ENV.fetch('SUPPORT_INSTANCE_SECRET'), endpoint: account.endpoint)
    Support::Transport.post(connection, '/internal/support/v1/accounts', { tenant_id: tenant.id.to_s, name: tenant.name })
    account.update!(name: tenant.name)
  end
end
