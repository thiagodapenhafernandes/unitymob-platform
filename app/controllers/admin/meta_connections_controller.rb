class Admin::MetaConnectionsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :require_pilot!

  def create
    nonce = SecureRandom.hex(32)
    url = client.register(nonce: nonce)
    session[:meta_central_attempt] = { 'nonce' => nonce, 'user_id' => current_admin_user.id,
      'tenant_id' => current_tenant.id, 'expires_at' => 10.minutes.from_now.to_i }
    redirect_to url, allow_other_host: true
  rescue Meta::CentralConnectionClient::Error
    redirect_to admin_meta_integrations_path, alert: 'Conexão central indisponível. Sua integração atual foi preservada; use a conexão legada.'
  end

  def show
    context = session.delete(:meta_central_attempt)
    handoff = params[:oauth_handoff].to_s
    unless context && context['user_id'] == current_admin_user.id && context['tenant_id'] == current_tenant.id &&
        context['expires_at'].to_i > Time.current.to_i && handoff.match?(/\A[0-9a-f]{64}\z/)
      return redirect_to admin_meta_integrations_path, alert: 'Retorno inválido ou expirado. Inicie a conexão novamente.'
    end
    identity = client.redeem(handoff: handoff, nonce: context.fetch('nonce'))
    integration = UserMetaIntegration.find_or_initialize_by(admin_user: current_admin_user, tenant_id: current_tenant.id)
    Meta::ConnectionCompletion.call(integration: integration, identity: identity, preserve_permissions: true)
    redirect_to admin_meta_integrations_path, notice: 'Facebook conectado. Estamos preparando os recursos em segundo plano.'
  rescue Meta::ConnectionCompletion::PermissionLoss => error
    redirect_to admin_meta_integrations_path, alert: error.message
  rescue StandardError => error
    Rails.logger.warn("[meta central] conclusão indisponível class=#{error.class}")
    redirect_to admin_meta_integrations_path, alert: 'Não foi possível concluir a conexão central. Sua integração atual foi preservada.'
  end

  private

  def client
    @client ||= Meta::CentralConnectionClient.new(tenant: current_tenant, user: current_admin_user)
  end

  def require_pilot!
    head :not_found unless Meta::CentralConnectionClient.enabled_for?(current_tenant) &&
      current_admin_user.tenant_id == current_tenant.id && request.base_url == client.origin
  rescue Meta::CentralConnectionClient::Error
    head :not_found
  end
end
