class Admin::MetaIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }
  before_action :set_integration
  before_action :set_page, only: [:list_forms]
  FORMS_PER_PAGE = 25

  def index
    # Show status and link to Facebook Login if not integrated
    @pages = @integration&.meta_facebook_pages || []
    @meta_webhook_mode = Meta::WebhookConfiguration.mode
    @meta_webhook_mode_label = Meta::WebhookConfiguration.label
    @meta_webhook_mode_description = Meta::WebhookConfiguration.description
    @meta_webhook_callback_url = Meta::WebhookConfiguration.callback_url
    @meta_webhook_verify_token = Meta::WebhookConfiguration.verify_token
  end

  def instagram
    raise ActiveRecord::RecordNotFound unless @integration
    page = @integration.meta_facebook_pages.find(params[:page_id])
    case params[:operation]
    when "discover" then Instagram::Connection.discover(page)
    when "activate" then Instagram::Connection.activate(page)
    when "deactivate" then page.update!(instagram_enabled: false)
    else return head :bad_request
    end
    redirect_to admin_meta_integrations_path, notice: "Configuração do Instagram atualizada."
  rescue Instagram::Connection::Error => error
    redirect_to admin_meta_integrations_path, alert: error.message
  rescue Koala::Facebook::APIError, Facebook::MetaService::MetaAPIError, ActiveRecord::RecordNotUnique
    redirect_to admin_meta_integrations_path, alert: "Não foi possível concluir. Verifique as permissões, o token da página e se o perfil já está ativado em outra conexão."
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

  def sync_pages
    trigger_sync(notice: "A sincronização foi iniciada em segundo plano.")
  end

  def sync_forms
    trigger_sync(notice: "A sincronização dos formulários foi iniciada.")
  end

  def ad_accounts
    raise ActiveRecord::RecordNotFound unless @integration

    if @integration.expired? || @integration.access_token.blank?
      @ad_accounts_error = "Conexão expirada. Atualize a autorização com o Facebook acima."
    else
      @ad_accounts = Facebook::MetaService.new(@integration.access_token).ad_accounts
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

    account_id = params.require(:meta_integration).permit(:ad_account_id)[:ad_account_id].to_s.delete_prefix("act_")
    if account_id.blank?
      @integration.update!(ad_account_id: nil, ad_account_name: nil)
    else
      raise ArgumentError unless account_id.match?(/\A[0-9]{5,30}\z/)
      account = Facebook::MetaService.new(@integration.access_token).ad_account(account_id)
      raise ArgumentError unless account["account_id"].to_s == account_id
      @integration.update!(ad_account_id: account_id, ad_account_name: account["name"])
    end
    redirect_to admin_meta_integrations_path, notice: "Conta de anúncios atualizada."
  rescue Koala::Facebook::APIError, ArgumentError
    redirect_to admin_meta_integrations_path, alert: "Não foi possível validar essa conta de anúncios. Confira o ID no Gerenciador de Anúncios e o acesso do usuário conectado à conta na Meta. Se necessário, solicite acesso ao administrador do negócio e atualize a autorização."
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

    integration.update!(sync_status: "processing", sync_progress: 0)
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

  def set_integration
    @integration = UserMetaIntegration.find_by(admin_user: current_admin_user, tenant_id: current_tenant.id)
  end

  def set_page
    raise ActiveRecord::RecordNotFound, "Integração Meta não encontrada" unless @integration

    @page = @integration.meta_facebook_pages.find(params[:page_id])
  end
end
