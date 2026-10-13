class Admin::AiIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :load_state

  PROVIDER_FORM_FIELDS = %i[
    auth_method
    api_key model_choice model_custom model
    voice_api_key voice_clear
    voice_model_choice voice_model_custom voice_model
    voice_transcription_model_choice voice_transcription_model_custom voice_transcription_model
  ].freeze

  def show
  end

  def update
    case ai_params[:section].to_s
    when "provider_connection"
      Setting.transaction do
        validate_provider_selection!
        update_module_bindings
        save_provider_selection
        update_content_credentials
        update_voice_pwa_settings
      end
      return redirect_to admin_ai_integration_path(anchor: "ai-integration-connections"), notice: "Conexões e vínculos dos módulos salvos com sucesso."
    when "search"
      update_search_settings
      return redirect_to admin_ai_integration_path(anchor: "ai-integration-voice"), notice: "Ajustes da busca inteligente salvos com sucesso."
    when "interest"
      update_interest_settings
      return redirect_to admin_ai_integration_path(anchor: "ai-integration-leads"), notice: "Inteligência de interesse salva com sucesso."
    when "seo"
      update_seo_settings
      return redirect_to admin_ai_integration_path(anchor: "ai-integration-content"), notice: "Instruções de SEO salvas com sucesso."
    when "diagnosis"
      update_diagnosis_settings
      return redirect_to admin_ai_integration_path(anchor: "ai-integration-data"), notice: "Diagnóstico do BI salvo com sucesso."
    end

    update_content_settings
    redirect_to admin_ai_integration_path(anchor: "ai-integration-content"), notice: "Configurações de IA salvas com sucesso."
  rescue => e
    redirect_to admin_ai_integration_path, alert: "Erro ao salvar IA: #{e.message}"
  end

  def generate_batch
    provider = Ai::ModuleConfiguration.new(:property_content, tenant: current_tenant).provider
    unless Ai::PropertyContentService.connected?(tenant: current_tenant)
      return redirect_to admin_ai_integration_path, alert: "Configure o token da #{provider.label} antes de iniciar o lote."
    end

    AiPropertyBatchSuggestionJob.perform_later(triggered_by_id: current_admin_user.id, tenant_id: current_tenant.id)
    redirect_to admin_ai_integration_path, notice: "Geração em lote iniciada em segundo plano. As sugestões não serão aplicadas automaticamente."
  rescue => e
    redirect_to admin_ai_integration_path, alert: "Erro ao iniciar lote: #{e.message}"
  end

  private

  def load_state
    @ai_provider = Ai::Provider.active_key(tenant: current_tenant)
    @active_provider = Ai::Provider.active(tenant: current_tenant)
    @content_connected = Ai::PropertyContentService.connected?(tenant: current_tenant)
    @voice_connected = Ai::PropertySearch::Configuration.voice_connected?(tenant: current_tenant)
    @property_enrichment_prompt = Ai::PropertyContentService.instructions(tenant: current_tenant)
    @response_parameters = Ai::PropertyContentService.response_parameters(tenant: current_tenant)
    @batch_status = tenant_setting_get("openai_batch_status", "idle")
    @batch_progress = tenant_setting_get("openai_batch_progress", "0").to_i.clamp(0, 100)
    @batch_message = tenant_setting_get("openai_batch_message", "Nenhum lote executado ainda.")
    @batch_last_at = Time.zone.parse(tenant_setting_get("openai_batch_last_at").to_s) rescue nil
    @dashboard_diagnosis_enabled = Dashboard::AiDiagnosis.enabled?(tenant: current_tenant)
    @dashboard_diagnosis_weekly_limit = Dashboard::AiDiagnosis.weekly_request_limit(tenant: current_tenant)
    @dashboard_diagnosis_monthly_budget_cents = Dashboard::AiDiagnosis.monthly_budget_cents(tenant: current_tenant)
    @dashboard_diagnosis_weekly_used = OpenAiUsageEvent.requests_count(tenant: current_tenant, feature: Dashboard::AiDiagnosis::FEATURE, since: Time.current.beginning_of_week)
    @dashboard_diagnosis_monthly_cost_cents = OpenAiUsageEvent.estimated_cost_cents(tenant: current_tenant, feature: Dashboard::AiDiagnosis::FEATURE, since: Time.current.beginning_of_month)
    @property_setting = PropertySetting.instance
    @layout_setting = LayoutSetting.instance
    @seo_strategy_prompt = Ai::SeoContentService.instructions(tenant: current_tenant)
    @seo_auto_inventory_enabled = Seo::PageTracker.enabled?(tenant: current_tenant)
    @seo_auto_apply_enabled = Seo::PageTracker.auto_apply?(tenant: current_tenant)
    @seo_auto_ai_enabled = Seo::PageTracker.auto_ai?(tenant: current_tenant)
    @seo_discovery_enabled = Seo::DiscoveryService.enabled?(tenant: current_tenant)
    # Escopado pelo tenant via habitation (AiPropertySuggestion não é TenantScoped)
    # — antes contava sugestões de TODAS as contas no painel.
    tenant_suggestions = AiPropertySuggestion.joins(:habitation)
                                             .where(habitations: { tenant_id: current_tenant.id })
    @pending_suggestions_count = tenant_suggestions.pending.count
    @failed_suggestions_count = tenant_suggestions.where(status: "failed").count
  end

  def validate_provider_selection!
    key = ai_params[:provider].to_s.strip
    raise ArgumentError, "Provedor de IA inválido." if key.present? && !Ai::Provider.all.key?(key)
  end

  def update_module_bindings
    return unless ai_params[:modules].present?

    default_provider = ai_params[:provider].presence || @ai_provider
    bindings = ai_params[:modules].to_h.to_h do |key, fields|
      if fields.key?("exception_enabled") && !ActiveModel::Type::Boolean.new.cast(fields["exception_enabled"])
        next [key, { "provider" => "", "model" => "" }]
      end
      provider_key = fields["provider"].to_s.strip
      model_fields = fields.fetch("models", {}).fetch(provider_key.presence || default_provider, {})
      model = selected_model_value(
        choice: model_fields["choice"], custom: model_fields["custom"], legacy: nil, default: ""
      )
      if Ai::Provider.custom?(model_fields["choice"]) && model_fields["custom"].blank?
        raise ArgumentError, "Informe o modelo personalizado do módulo."
      end
      [key, { "provider" => provider_key, "model" => model }]
    end
    Ai::ModuleConfiguration.save!(bindings, tenant: current_tenant)
  end

  def save_provider_selection
    key = ai_params[:provider].to_s.strip
    return if key.blank?

    tenant_setting_set(Ai::Provider::SETTING, Ai::Provider.find(key).key, "Provedor de IA ativo da conta")
  end

  def update_content_credentials
    provider_forms_params.each do |provider_key, fields|
      provider = Ai::Provider.find(provider_key)
      token = fields[:api_key].to_s.strip
      model = selected_model_value(
        choice: fields[:model_choice],
        custom: fields[:model_custom],
        legacy: fields[:model],
        default: provider.default_model
      )

      tenant_setting_set(provider.api_key_setting, token, "Token #{provider.label} para conteúdo") if token.present?
      tenant_setting_set(provider.model_setting, model, "Modelo #{provider.label} para enriquecimento de imóveis") if fields.keys.any? { |key| %w[model_choice model_custom model].include?(key) }
    end
  end

  def update_content_settings
    prompt = ai_params[:property_enrichment_prompt].to_s
    tenant_setting_set(Ai::PropertyContentService::PROMPT_SETTING, prompt, "Instruções de IA para título e descrição dos imóveis")
    Ai::PropertyContentService::RESPONSE_PARAMETER_SETTINGS.each do |key, setting_key|
      tenant_setting_set(
        setting_key,
        Ai::PropertyContentService.normalize_response_parameter(key, ai_params[key]).to_s,
        "Parâmetro #{key} da IA para título e descrição dos imóveis"
      )
    end
  end

  def update_diagnosis_settings
    budget_cents = if ai_params.key?(:dashboard_diagnosis_monthly_budget_reais)
      Dashboard::AiDiagnosis.budget_reais_to_cents(ai_params[:dashboard_diagnosis_monthly_budget_reais])
    elsif ai_params.key?(:dashboard_diagnosis_monthly_budget_cents)
      ai_params[:dashboard_diagnosis_monthly_budget_cents].to_i.clamp(0, 100_000)
    end
    if ai_params.key?(:dashboard_diagnosis_enabled)
      tenant_setting_set(Dashboard::AiDiagnosis::ENABLED_SETTING, ActiveModel::Type::Boolean.new.cast(ai_params[:dashboard_diagnosis_enabled]).to_s, "Habilita diagnóstico textual do BI com IA")
    end
    if ai_params.key?(:dashboard_diagnosis_weekly_limit)
      tenant_setting_set(Dashboard::AiDiagnosis::WEEKLY_REQUEST_LIMIT_SETTING, ai_params[:dashboard_diagnosis_weekly_limit].to_i.clamp(0, 10).to_s, "Limite semanal de diagnósticos do BI com IA")
    end
    unless budget_cents.nil?
      tenant_setting_set(Dashboard::AiDiagnosis::MONTHLY_BUDGET_CENTS_SETTING, budget_cents.to_s, "Teto mensal estimado do diagnóstico do BI com IA")
    end
  end

  def update_search_settings
    unless @property_setting.update(search_params)
      raise StandardError, @property_setting.errors.full_messages.to_sentence
    end
  end

  def update_interest_settings
    unless @layout_setting.update(interest_params)
      raise StandardError, @layout_setting.errors.full_messages.to_sentence
    end
  end

  def update_seo_settings
    Seo::StrategySettings.save!(
      auto_inventory: params[:seo_auto_inventory_enabled] == "1",
      auto_apply: params[:seo_auto_apply_enabled] == "1",
      auto_ai: params[:seo_ai_auto_generate_enabled] == "1",
      discovery: params[:seo_discovery_enabled] == "1",
      prompt: params[:seo_ai_strategy_prompt],
      tenant: current_tenant
    )
  end

  def search_params
    params.require(:property_setting).permit(*PropertySetting::AI_SEARCH_FORM_FIELDS)
  end

  def interest_params
    attributes = params.require(:layout_setting).permit(
      :interest_intelligence_enabled,
      :interest_intelligence_instructions,
      interest_intelligence_settings: {}
    )
    InterestIntelligence::Settings.normalize_form_params(attributes)
  end

  def update_voice_pwa_settings
    provider_forms_params.each do |provider_key, fields|
      provider = Ai::Provider.find(provider_key)
      token = fields[:voice_api_key].to_s.strip
      model = selected_model_value(
        choice: fields[:voice_model_choice],
        custom: fields[:voice_model_custom],
        legacy: fields[:voice_model],
        default: provider.default_model
      )
      transcription_model = selected_model_value(
        choice: fields[:voice_transcription_model_choice],
        custom: fields[:voice_transcription_model_custom],
        legacy: fields[:voice_transcription_model],
        default: provider.default_transcription_model
      )

      if ActiveModel::Type::Boolean.new.cast(fields[:voice_clear])
        tenant_setting_set(provider.voice_api_key_setting, "", "Token dedicado #{provider.label} para Voice PWA")
      elsif token.present?
        tenant_setting_set(provider.voice_api_key_setting, token, "Token dedicado #{provider.label} para Voice PWA")
      end

      tenant_setting_set(provider.voice_model_setting, model, "Modelo #{provider.label} para interpretação da busca do Voice PWA") if fields.keys.any? { |key| %w[voice_model_choice voice_model_custom voice_model].include?(key) }
      tenant_setting_set(provider.voice_transcription_model_setting, transcription_model, "Modelo #{provider.label} para transcrição do Voice PWA") if fields.keys.any? { |key| %w[voice_transcription_model_choice voice_transcription_model_custom voice_transcription_model].include?(key) }
    end
  end

  def provider_forms_params
    ai_params[:providers] || {}
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
      :provider,
      :property_enrichment_prompt,
      :temperature,
      :top_p,
      :frequency_penalty,
      :presence_penalty,
      :dashboard_diagnosis_enabled,
      :dashboard_diagnosis_weekly_limit,
      :dashboard_diagnosis_monthly_budget_cents,
      :dashboard_diagnosis_monthly_budget_reais,
      providers: Ai::Provider.all.keys.index_with { PROVIDER_FORM_FIELDS },
      modules: Ai::ModuleConfiguration::MODULES.keys.index_with { [:provider, :exception_enabled, { models: Ai::Provider.all.keys.index_with { %i[choice custom] } }] }
    )
  end

  def selected_model_value(choice:, custom:, legacy:, default:)
    selected = choice.to_s.strip

    if Ai::Provider.custom?(selected)
      custom.to_s.strip.presence || legacy.to_s.strip.presence || default
    elsif selected.present?
      selected
    else
      legacy.to_s.strip.presence || default
    end
  end
end
