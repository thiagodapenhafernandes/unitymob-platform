class Admin::MetaIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :set_integration
  before_action :require_meta_impersonation!, only: [:selected_pages]
  before_action :set_page, only: [:list_forms]
  FORMS_PER_PAGE = 25

  def index
    # Show status and link to Facebook Login if not integrated
    @pages = @integration ? @integration.meta_facebook_pages.enabled.where(page_id: @integration.selected_page_ids) : []
    @meta_webhook_mode = Meta::WebhookConfiguration.mode
    @meta_webhook_mode_description = Meta::WebhookConfiguration.description
    @meta_webhook_callback_url = Meta::WebhookConfiguration.callback_url
    @meta_webhook_verify_token = Meta::WebhookConfiguration.verify_token
  end

  def permissions
    raise ActiveRecord::RecordNotFound unless @integration

    @permission_check = Facebook::PermissionCheck.call(@integration)
    render :permissions
  end

  def list_forms
    @forms_per_page = FORMS_PER_PAGE
    @forms_total_count = @page.meta_lead_forms.count
    total_pages = [(@forms_total_count.to_f / @forms_per_page).ceil, 1].max
    requested_page = [params[:page].to_i, 1].max
    @page_number = [requested_page, total_pages].min
    @forms = @page.meta_lead_forms
                  .order(facebook_created_at: :desc, id: :desc)
                  .offset((@page_number - 1) * @forms_per_page)
                  .limit(@forms_per_page)
    @next_page = @forms_total_count > (@page_number * @forms_per_page) ? @page_number + 1 : nil
    @frame_id = if @page_number == 1
      "page_forms_#{@page.id}"
    else
      "page_forms_#{@page.id}_page_#{@page_number}"
    end
    render layout: false
  end

  def selected_pages
    raise ActiveRecord::RecordNotFound unless @integration
    ids = Array(params.require(:meta_integration).permit(selected_page_ids: [])[:selected_page_ids]).reject(&:blank?).uniq
    known = @integration.meta_facebook_pages.where(page_id: ids).pluck(:page_id)
    return head :unprocessable_entity unless (ids - known).empty?

    @integration.with_lock do
      @integration.update!(selected_page_ids: ids)
      @integration.meta_facebook_pages.where.not(page_id: ids).update_all(active: false, instagram_enabled: false)
    end
    trigger_sync(notice: "Seleção salva para esta conta. Sincronização iniciada em segundo plano.")
  end

  def sync_pages
    trigger_sync(notice: "A sincronização foi iniciada em segundo plano.")
  end

  def sync_forms
    trigger_sync(notice: "A sincronização dos formulários foi iniciada.")
  end

  def ad_accounts
    return head :forbidden if params[:all] == "1" && !impersonating_admin_user?
    raise ActiveRecord::RecordNotFound unless @integration

    if @integration.expired? || @integration.access_token.blank?
      @ad_accounts_error = "Conexão expirada. Atualize a autorização com o Facebook acima."
    else
      @ad_accounts = Facebook::MetaService.new(@integration.access_token).ad_accounts(all: params[:all] == "1", page_ids: @integration.selected_page_ids)
    end
  rescue Koala::Facebook::APIError => error
    @ad_accounts_error = case error.fb_error_code.to_i
    when 190 then "A Meta recusou o token. Atualize a autorização com o Facebook acima."
    when 10, 200 then "A Meta recusou o acesso às contas de anúncios. Verifique as permissões acima e solicite acesso ao administrador do negócio."
    else "Não foi possível consultar as contas na Meta. Tente novamente; isso não significa que não existem contas disponíveis."
    end
  rescue Faraday::Error, Timeout::Error, SocketError
    @ad_accounts_error = "A consulta à Meta está indisponível. Tente novamente em instantes."
  end

  def ad_account
    raise ActiveRecord::RecordNotFound unless @integration

    permitted = params.require(:meta_integration).permit(:ad_account_id, ad_account_ids: [])
    ids = Array(permitted.key?(:ad_account_ids) ? permitted[:ad_account_ids] : permitted[:ad_account_id])
      .map { |id| id.to_s.delete_prefix("act_") }.reject(&:blank?).uniq
    raise ArgumentError unless ids.all? { |id| id.match?(/\A[0-9]{5,30}\z/) }

    accounts = {}
    if ids.any?
      service = Facebook::MetaService.new(@integration.access_token)
      unless impersonating_admin_user?
        allowed = service.ad_accounts(page_ids: @integration.selected_page_ids).map { |item| item["account_id"].to_s }
        return head :forbidden unless (ids - allowed).empty?
      end
      ids.each do |id|
        account = service.ad_account(id)
        raise ArgumentError unless account["account_id"].to_s == id
        accounts[id] = account["name"]
      end
    end
    @integration.update!(ad_accounts: accounts, ad_account_id: ids.first, ad_account_name: accounts[ids.first])
    redirect_to admin_meta_integrations_path, notice: "Contas de anúncios atualizadas."
  rescue Koala::Facebook::APIError, Facebook::MetaService::MetaAPIError, Faraday::Error, Timeout::Error, SocketError, ArgumentError
    redirect_to admin_meta_integrations_path, alert: "Não foi possível validar as contas de anúncios. Confira os IDs no Gerenciador de Anúncios e o acesso do usuário conectado à conta na Meta. Se necessário, solicite acesso ao administrador do negócio e atualize a autorização."
  end

  def disconnect
    @integration&.destroy
    redirect_to admin_meta_integrations_path, notice: "Conta do Facebook desconectada."
  end

  private

  # Dispara o MetaSyncJob usando SOMENTE a integração do usuário logado —
  # modelo agência: cada usuário conecta o próprio Facebook e sincroniza as
  # próprias páginas. Responde JSON para o botão "Sincronizar agora" das
  # regras de distribuição dar feedback honesto.
  def trigger_sync(notice:)
    integration = @integration

    if integration.nil?
      message = "Você não tem uma conta Meta conectada. Conecte seu Facebook em Configurações → Integrações Meta."
      respond_to do |format|
        format.json { render json: { ok: false, message: message }, status: :unprocessable_content }
        format.html { redirect_to admin_meta_integrations_path, alert: message }
      end
      return
    end

    integration.update!(sync_status: "processing", sync_progress: 0, sync_message: "Aguardando início da sincronização…", last_sync_error: nil)
    MetaSyncJob.perform_later(integration.id)
    respond_to do |format|
      format.json { render json: { ok: true, message: notice } }
      format.html { redirect_to admin_meta_integrations_path, notice: notice }
    end
  rescue StandardError => e
    Rails.logger.error("[MetaSync] enqueue failed integration_id=#{integration&.id} error=#{e.class}")
    message = "Não foi possível iniciar a sincronização. Tente novamente em instantes."
    integration&.update_columns(sync_status: "failed", sync_message: message, last_sync_error: "Falha ao colocar a sincronização na fila. Tente novamente; se persistir, contate o suporte.")

    respond_to do |format|
      format.json { render json: { ok: false, message: message }, status: :internal_server_error }
      format.html { redirect_to admin_meta_integrations_path, alert: message }
    end
  end

  def require_meta_impersonation!
    head :forbidden unless impersonating_admin_user?
  end

  def set_integration
    @integration = UserMetaIntegration.find_by(admin_user: current_admin_user, tenant_id: current_tenant.id)
  end

  def set_page
    raise ActiveRecord::RecordNotFound, "Integração Meta não encontrada" unless @integration

    @page = @integration.meta_facebook_pages.where(page_id: @integration.selected_page_ids).find(params[:page_id])
  end
end
