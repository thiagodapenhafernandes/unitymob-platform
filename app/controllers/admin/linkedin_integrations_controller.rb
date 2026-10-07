class Admin::LinkedinIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :set_integration
  rescue_from Linkedin::Client::Error, with: :connection_error

  def show
  end

  def connect
    unless LinkedinIntegration.configured?
      return redirect_to admin_linkedin_integration_path, alert: "A integração LinkedIn ainda precisa ser habilitada pelo suporte."
    end
    state = SecureRandom.hex(32)
    session[:linkedin_oauth] = { state: state, tenant_id: current_tenant.id, admin_user_id: current_admin_user.id, expires_at: 10.minutes.from_now.to_i }
    redirect_to Linkedin::Client.new.authorization_url(state: state), allow_other_host: true
  end

  def callback
    oauth = session.delete(:linkedin_oauth)&.with_indifferent_access
    unless oauth && oauth[:expires_at].to_i > Time.current.to_i && oauth[:tenant_id] == current_tenant.id && oauth[:admin_user_id] == current_admin_user.id && params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(oauth[:state], params[:state].to_s)
      return redirect_to admin_linkedin_integration_path, alert: "Não foi possível validar o retorno do LinkedIn. Conecte novamente."
    end
    if params[:error].present?
      return redirect_to admin_linkedin_integration_path, alert: "A autorização do LinkedIn não foi concluída. Tente conectar novamente."
    end
    tokens = Linkedin::Client.new.exchange_code(params[:code])
    raise Linkedin::Client::Error, "O LinkedIn não retornou uma autorização válida." if tokens["access_token"].blank? || tokens["expires_in"].to_i <= 0
    @integration ||= LinkedinIntegration.new(tenant: current_tenant)
    @integration.update!(admin_user: current_admin_user, access_token: tokens["access_token"], token_expires_at: tokens["expires_in"].to_i.seconds.from_now, last_error: nil)
    LinkedinSyncJob.perform_later(@integration.id, refresh_catalog: true)
    redirect_to admin_linkedin_integration_path, notice: "LinkedIn conectado. Estamos buscando suas contas de anúncios."
  end

  def update
    raise ActiveRecord::RecordNotFound unless @integration&.connected?
    ids = Array(params.require(:linkedin_integration).permit(selected_account_ids: [])[:selected_account_ids]).compact_blank.map(&:to_s).uniq
    @integration.with_lock do
      known_ids = @integration.ad_accounts.pluck("id")
      return head :unprocessable_content unless (ids - known_ids).empty?
      now = (Time.current.to_f * 1000).to_i
      cursors = @integration.account_cursors.slice(*ids)
      ids.each { |id| cursors[id] ||= { "since" => now } }
      @integration.update!(selected_account_ids: ids, account_cursors: cursors)
    end
    LinkedinSyncJob.perform_later(@integration.id, refresh_catalog: true)
    redirect_to admin_linkedin_integration_path, notice: "Contas salvas. Novos leads serão recebidos automaticamente; escolha campanhas e formulários nas regras de distribuição."
  end

  def sync
    raise ActiveRecord::RecordNotFound unless @integration&.connected?
    LinkedinSyncJob.perform_later(@integration.id, refresh_catalog: true)
    redirect_to admin_linkedin_integration_path, notice: "Atualização iniciada. Recarregue a tela em instantes."
  end

  def disconnect
    @integration&.with_lock do
      @integration.update!(access_token: nil, token_expires_at: nil, selected_account_ids: [], account_cursors: {}, catalog: {}, ad_accounts: [], last_error: nil)
    end
    redirect_to admin_linkedin_integration_path, notice: "LinkedIn desconectado. Os leads já recebidos foram preservados."
  end

  private

  def set_integration
    @integration = LinkedinIntegration.find_by(tenant: current_tenant)
  end

  def connection_error(error)
    redirect_to admin_linkedin_integration_path, alert: error.message
  end
end
