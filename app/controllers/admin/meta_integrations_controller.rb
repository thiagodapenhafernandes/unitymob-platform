class Admin::MetaIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }
  before_action :set_integration
  before_action :set_page, only: [:list_forms]
  FORMS_PER_PAGE = 25

  def index
    # Show status and link to Facebook Login if not integrated
    @pages = @integration&.meta_facebook_pages || []
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

    respond_to do |format|
      format.json { render json: { ok: false, message: message }, status: :internal_server_error }
      format.html { redirect_to admin_meta_integrations_path, alert: message }
    end
  end

  def set_integration
    @integration = UserMetaIntegration.find_by(admin_user: current_admin_user)
  end

  def set_page
    raise ActiveRecord::RecordNotFound, "Integração Meta não encontrada" unless @integration

    @page = @integration.meta_facebook_pages.find(params[:page_id])
  end
end
