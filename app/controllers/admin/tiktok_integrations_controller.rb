class Admin::TiktokIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :set_integration
  rescue_from Tiktok::Client::Error, with: :connection_error

  def show
  end

  def connect
    unless TiktokIntegration.configured?
      return redirect_to admin_tiktok_integration_path, alert: "A integração TikTok precisa ser habilitada pelo suporte."
    end
    state = SecureRandom.hex(32)
    Tiktok::GatewayClient.register_oauth!(state: state, return_url: callback_admin_tiktok_integration_url)
    cookies.encrypted[:tiktok_oauth] = {
      value: { state: state, tenant_id: current_tenant.id, admin_user_id: current_admin_user.id, expires_at: 10.minutes.from_now.to_i },
      expires: 10.minutes.from_now, httponly: true, secure: request.ssl?, same_site: :lax
    }
    redirect_to Tiktok::Client.new.authorization_url(state: state), allow_other_host: true
  end

  def callback
    oauth = cookies.encrypted[:tiktok_oauth]&.with_indifferent_access
    cookies.delete(:tiktok_oauth)
    unless oauth && oauth[:expires_at].to_i > Time.current.to_i && oauth[:tenant_id] == current_tenant.id &&
        oauth[:admin_user_id] == current_admin_user.id && params[:state].present? &&
        ActiveSupport::SecurityUtils.secure_compare(oauth[:state], params[:state].to_s)
      return redirect_to admin_tiktok_integration_path, alert: "Não foi possível validar o retorno do TikTok. Conecte novamente."
    end
    tokens = Tiktok::Client.new.exchange_code(params[:auth_code])
    raise Tiktok::Client::Error, "O TikTok não retornou uma autorização válida." if tokens["access_token"].blank?
    accounts = Tiktok::Client.new(tokens.fetch("access_token")).accounts
    @integration ||= TiktokIntegration.new(tenant: current_tenant, admin_user: current_admin_user)
    @integration.with_lock do
      if @integration.persisted? && @integration.connected?
        client = Tiktok::Client.new(@integration.access_token)
        client.subscriptions.each do |row|
          next unless Tiktok::GatewayClient.owns_callback?(row["callback_url"], @integration)
          client.unsubscribe(row.fetch("subscription_id"))
        end
      end
      @integration.update!(subscriptions: {}, admin_user: current_admin_user, access_token: tokens.fetch("access_token"), ad_accounts: accounts, last_error: nil)
    end
    TiktokSyncJob.perform_later(@integration.id)
    redirect_to admin_tiktok_integration_path, notice: "TikTok conectado. Selecione os anunciantes que enviarão leads."
  end

  def update
    raise ActiveRecord::RecordNotFound unless @integration&.connected?
    ids = Array(params.require(:tiktok_integration).permit(selected_account_ids: [])[:selected_account_ids]).compact_blank.map(&:to_s).uniq
    @integration.with_lock do
      return head :unprocessable_entity unless (ids - @integration.ad_accounts.pluck("advertiser_id").map(&:to_s)).empty?
      @integration.update!(selected_account_ids: ids)
    end
    TiktokSyncJob.perform_later(@integration.id)
    redirect_to admin_tiktok_integration_path, notice: "Anunciantes salvos. Estamos atualizando o recebimento de leads."
  end

  def sync
    raise ActiveRecord::RecordNotFound unless @integration&.connected?
    TiktokSyncJob.perform_later(@integration.id)
    redirect_to admin_tiktok_integration_path, notice: "Atualização do TikTok iniciada."
  end

  def disconnect
    @integration&.update!(selected_account_ids: [])
    @integration&.with_lock do
      Tiktok::GatewayClient.pause_unselected!(@integration)
      client = Tiktok::Client.new(@integration.access_token)
      client.subscriptions.each do |row|
        next unless Tiktok::GatewayClient.owns_callback?(row["callback_url"], @integration)
        client.unsubscribe(row.fetch("subscription_id"))
      end
      @integration.update!(subscriptions: {}, access_token: nil, catalog: {}, ad_accounts: [], last_error: nil)
    end
    redirect_to admin_tiktok_integration_path, notice: "TikTok desconectado. Os leads recebidos foram preservados."
  end

  private

  def set_integration
    @integration = TiktokIntegration.find_by(tenant: current_tenant)
  end

  def connection_error(error)
    @integration&.update_columns(last_error: error.message)
    redirect_to admin_tiktok_integration_path, alert: error.message
  end
end
