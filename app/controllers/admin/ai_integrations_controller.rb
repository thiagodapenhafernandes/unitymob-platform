class Admin::AiIntegrationsController < Admin::BaseController
  before_action :require_admin!
  before_action :load_state

  def show
  end

  def update
    if ai_params[:section].to_s == "voice_pwa"
      update_voice_pwa_settings
      return redirect_to admin_ai_integration_path(anchor: "ai-integration-voice"), notice: "Configurações do Voice PWA salvas com sucesso."
    end

    update_content_settings
    redirect_to admin_ai_integration_path, notice: "Configurações de IA salvas com sucesso."
  rescue => e
    redirect_to admin_ai_integration_path, alert: "Erro ao salvar IA: #{e.message}"
  end

  def generate_batch
    unless Ai::PropertyContentService.connected?(tenant: current_tenant)
      return redirect_to admin_ai_integration_path, alert: "Configure o token da OpenAI antes de iniciar o lote."
    end

    AiPropertyBatchSuggestionJob.perform_later(triggered_by_id: current_admin_user.id, tenant_id: current_tenant.id)
    redirect_to admin_ai_integration_path, notice: "Geração em lote iniciada em segundo plano. As sugestões não serão aplicadas automaticamente."
  rescue => e
    redirect_to admin_ai_integration_path, alert: "Erro ao iniciar lote: #{e.message}"
  end

  private

  def load_state
    @openai_connected = Ai::PropertyContentService.connected?(tenant: current_tenant)
    @openai_api_key = Ai::PropertyContentService.api_key(tenant: current_tenant)
    @openai_model = Ai::PropertyContentService.model(tenant: current_tenant)
    @openai_model_options = OpenAi::ModelCatalog.response_model_options(api_key: @openai_api_key, selected: @openai_model)
    @openai_model_custom = model_custom_value(@openai_model, response: true)
    @openai_prompt = Ai::PropertyContentService.instructions(tenant: current_tenant)
    @openai_response_parameters = Ai::PropertyContentService.response_parameters(tenant: current_tenant)
    @property_search_connected = Ai::PropertySearch::Configuration.connected?(tenant: current_tenant)
    @property_search_dedicated_token = Ai::PropertySearch::Configuration.dedicated_api_key_configured?(tenant: current_tenant)
    @property_search_api_key = Ai::PropertySearch::Configuration.api_key(tenant: current_tenant)
    @property_search_model = Ai::PropertySearch::Configuration.model(tenant: current_tenant)
    @property_search_model_options = OpenAi::ModelCatalog.response_model_options(api_key: @property_search_api_key, selected: @property_search_model)
    @property_search_model_custom = model_custom_value(@property_search_model, response: true)
    @property_search_transcription_model = Ai::PropertySearch::Configuration.transcription_model(tenant: current_tenant)
    @property_search_transcription_model_options = OpenAi::ModelCatalog.transcription_model_options(api_key: @property_search_api_key, selected: @property_search_transcription_model)
    @property_search_transcription_model_custom = model_custom_value(@property_search_transcription_model, response: false)
    @batch_status = tenant_setting_get("openai_batch_status", "idle")
    @batch_progress = tenant_setting_get("openai_batch_progress", "0").to_i.clamp(0, 100)
    @batch_message = tenant_setting_get("openai_batch_message", "Nenhum lote executado ainda.")
    @batch_last_at = Time.zone.parse(tenant_setting_get("openai_batch_last_at").to_s) rescue nil
    @dashboard_diagnosis_enabled = Dashboard::AiDiagnosis.enabled?(tenant: current_tenant)
    @dashboard_diagnosis_weekly_limit = Dashboard::AiDiagnosis.weekly_request_limit(tenant: current_tenant)
    @dashboard_diagnosis_monthly_budget_cents = Dashboard::AiDiagnosis.monthly_budget_cents(tenant: current_tenant)
    @dashboard_diagnosis_weekly_used = OpenAiUsageEvent.requests_count(tenant: current_tenant, feature: Dashboard::AiDiagnosis::FEATURE, since: Time.current.beginning_of_week)
    @dashboard_diagnosis_monthly_cost_cents = OpenAiUsageEvent.estimated_cost_cents(tenant: current_tenant, feature: Dashboard::AiDiagnosis::FEATURE, since: Time.current.beginning_of_month)
    # Escopado pelo tenant via habitation (AiPropertySuggestion não é TenantScoped)
    # — antes contava sugestões de TODAS as contas no painel.
    tenant_suggestions = AiPropertySuggestion.joins(:habitation)
                                             .where(habitations: { tenant_id: current_tenant.id })
    @pending_suggestions_count = tenant_suggestions.pending.count
    @failed_suggestions_count = tenant_suggestions.where(status: "failed").count
  end

  def update_content_settings
    permitted = ai_params.to_h.with_indifferent_access
    token = permitted[:api_key].to_s.strip
    model = selected_model_value(
      choice: permitted[:model_choice],
      custom: permitted[:model_custom],
      legacy: permitted[:model],
      default: Ai::PropertyContentService::DEFAULT_MODEL
    )
    prompt = permitted[:property_enrichment_prompt].to_s

    tenant_setting_set(Ai::PropertyContentService::API_KEY_SETTING, token, "Token da OpenAI") if token.present?
    tenant_setting_set(Ai::PropertyContentService::MODEL_SETTING, model, "Modelo OpenAI para enriquecimento de imóveis")
    tenant_setting_set(Ai::PropertyContentService::PROMPT_SETTING, prompt, "Instruções de IA para título e descrição dos imóveis")
    Ai::PropertyContentService::RESPONSE_PARAMETER_SETTINGS.each do |key, setting_key|
      tenant_setting_set(
        setting_key,
        Ai::PropertyContentService.normalize_response_parameter(key, permitted[key]).to_s,
        "Parâmetro #{key} da OpenAI para título e descrição dos imóveis"
      )
    end
    if permitted.key?(:dashboard_diagnosis_enabled)
      tenant_setting_set(Dashboard::AiDiagnosis::ENABLED_SETTING, ActiveModel::Type::Boolean.new.cast(permitted[:dashboard_diagnosis_enabled]).to_s, "Habilita diagnóstico textual do BI com OpenAI")
    end
    if permitted.key?(:dashboard_diagnosis_weekly_limit)
      tenant_setting_set(Dashboard::AiDiagnosis::WEEKLY_REQUEST_LIMIT_SETTING, permitted[:dashboard_diagnosis_weekly_limit].to_i.clamp(0, 10).to_s, "Limite semanal de diagnósticos do BI com OpenAI")
    end
    if permitted.key?(:dashboard_diagnosis_monthly_budget_cents)
      tenant_setting_set(Dashboard::AiDiagnosis::MONTHLY_BUDGET_CENTS_SETTING, permitted[:dashboard_diagnosis_monthly_budget_cents].to_i.clamp(0, 100_000).to_s, "Teto mensal estimado do diagnóstico do BI com OpenAI")
    end
  end

  def update_voice_pwa_settings
    token = ai_params[:property_search_api_key].to_s.strip
    model = selected_model_value(
      choice: ai_params[:property_search_model_choice],
      custom: ai_params[:property_search_model_custom],
      legacy: ai_params[:property_search_model],
      default: Ai::PropertySearch::Configuration::DEFAULT_MODEL
    )
    transcription_model = selected_model_value(
      choice: ai_params[:property_search_transcription_model_choice],
      custom: ai_params[:property_search_transcription_model_custom],
      legacy: ai_params[:property_search_transcription_model],
      default: Ai::PropertySearch::Configuration::DEFAULT_TRANSCRIPTION_MODEL
    )

    if ActiveModel::Type::Boolean.new.cast(ai_params[:clear_property_search_api_key])
      tenant_setting_set(Ai::PropertySearch::Configuration::API_KEY_SETTING, "", "Token dedicado da OpenAI para Voice PWA")
    elsif token.present?
      tenant_setting_set(Ai::PropertySearch::Configuration::API_KEY_SETTING, token, "Token dedicado da OpenAI para Voice PWA")
    end

    tenant_setting_set(Ai::PropertySearch::Configuration::MODEL_SETTING, model, "Modelo OpenAI para interpretação da busca do Voice PWA")
    tenant_setting_set(Ai::PropertySearch::Configuration::TRANSCRIPTION_MODEL_SETTING, transcription_model, "Modelo OpenAI para transcrição do Voice PWA")
  end

  def tenant_setting_get(key, default = nil)
    Setting.tenant_get(key, default, tenant: current_tenant)
  end

  def tenant_setting_set(key, value, description)
    Setting.set(key, value, description, tenant: current_tenant)
  end

  def ai_params
    params.require(:ai).permit(
      :section,
      :api_key,
      :model_choice,
      :model_custom,
      :model,
      :property_enrichment_prompt,
      :temperature,
      :top_p,
      :frequency_penalty,
      :presence_penalty,
      :dashboard_diagnosis_enabled,
      :dashboard_diagnosis_weekly_limit,
      :dashboard_diagnosis_monthly_budget_cents,
      :property_search_api_key,
      :clear_property_search_api_key,
      :property_search_model_choice,
      :property_search_model_custom,
      :property_search_model,
      :property_search_transcription_model_choice,
      :property_search_transcription_model_custom,
      :property_search_transcription_model
    )
  end

  def selected_model_value(choice:, custom:, legacy:, default:)
    selected = choice.to_s.strip

    if OpenAi::ModelCatalog.custom?(selected)
      custom.to_s.strip.presence || legacy.to_s.strip.presence || default
    elsif selected.present?
      selected
    else
      legacy.to_s.strip.presence || default
    end
  end

  def model_custom_value(model, response:)
    return "" if OpenAi::ModelCatalog.automatic?(model)

    known = response ? OpenAi::ModelCatalog.known_response_model?(model) : OpenAi::ModelCatalog.known_transcription_model?(model)
    known ? "" : model.to_s.strip
  end
end
