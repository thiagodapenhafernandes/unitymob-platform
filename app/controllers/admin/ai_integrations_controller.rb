class Admin::AiIntegrationsController < Admin::BaseController
  before_action :require_admin!
  before_action :load_state

  def show
  end

  def update
    token = ai_params[:api_key].to_s.strip
    model = ai_params[:model].to_s.strip.presence || Ai::PropertyContentService::DEFAULT_MODEL
    prompt = ai_params[:property_enrichment_prompt].to_s

    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, token, "Token da OpenAI") if token.present?
    Setting.set(Ai::PropertyContentService::MODEL_SETTING, model, "Modelo OpenAI para enriquecimento de imóveis")
    Setting.set(Ai::PropertyContentService::PROMPT_SETTING, prompt, "Instruções de IA para título e descrição dos imóveis")

    redirect_to admin_ai_integration_path, notice: "Configurações de IA salvas com sucesso."
  rescue => e
    redirect_to admin_ai_integration_path, alert: "Erro ao salvar IA: #{e.message}"
  end

  def generate_batch
    unless Ai::PropertyContentService.connected?
      return redirect_to admin_ai_integration_path, alert: "Configure o token da OpenAI antes de iniciar o lote."
    end

    AiPropertyBatchSuggestionJob.perform_later(triggered_by_id: current_admin_user.id, tenant_id: current_tenant.id)
    redirect_to admin_ai_integration_path, notice: "Geração em lote iniciada em segundo plano. As sugestões não serão aplicadas automaticamente."
  rescue => e
    redirect_to admin_ai_integration_path, alert: "Erro ao iniciar lote: #{e.message}"
  end

  private

  def load_state
    @openai_connected = Ai::PropertyContentService.connected?
    @openai_model = Ai::PropertyContentService.model
    @openai_prompt = Ai::PropertyContentService.instructions
    @batch_status = Setting.get("openai_batch_status", "idle")
    @batch_progress = Setting.get("openai_batch_progress", "0").to_i.clamp(0, 100)
    @batch_message = Setting.get("openai_batch_message", "Nenhum lote executado ainda.")
    @batch_last_at = Time.zone.parse(Setting.get("openai_batch_last_at").to_s) rescue nil
    # Escopado pelo tenant via habitation (AiPropertySuggestion não é TenantScoped)
    # — antes contava sugestões de TODAS as contas no painel.
    tenant_suggestions = AiPropertySuggestion.joins(:habitation)
                                             .where(habitations: { tenant_id: current_tenant.id })
    @pending_suggestions_count = tenant_suggestions.pending.count
    @failed_suggestions_count = tenant_suggestions.where(status: "failed").count
  end

  def ai_params
    params.require(:ai).permit(:api_key, :model, :property_enrichment_prompt)
  end
end
