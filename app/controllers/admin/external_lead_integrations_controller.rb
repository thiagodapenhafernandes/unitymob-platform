class Admin::ExternalLeadIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :load_integration

  def show
    @webhook_url = @integration.persisted? ? external_lead_webhook_url : nil
    @lead_pipeline_stages = current_tenant.lead_pipeline_stages.includes(:lead_pipeline).ordered
    @recent_external_leads = if @integration.persisted?
      current_tenant.leads
                    .where(external_lead_integration: @integration)
                    .includes(:admin_user)
                    .order(external_last_synced_at: :desc, updated_at: :desc)
                    .limit(8)
    else
      Lead.none
    end
    @seller_rows = seller_rows
    @external_stage_options = external_stage_options
    @operational_mapping_rows = operational_mapping_rows
  end

  def update
    attrs = external_lead_params.to_h
    token = attrs.delete("access_token").to_s.strip
    enabled_requested = extract_enabled_request(attrs)
    webhook_listening_param_present = attrs.key?("webhook_listening_enabled")
    webhook_listening_requested = extract_webhook_listening_request!(attrs)

    @integration.assign_attributes(attrs)
    @integration.access_token = token if token.present?
    @integration.connected_by_admin_user = current_admin_user if token.present?
    raise "Token da API externa obrigatório para habilitar a escuta de novos leads." if enabled_requested && webhook_listening_requested && @integration.access_token.blank?

    unless enabled_requested
      notice = deactivate_integration_locally!
      redirect_to admin_external_lead_integration_path, notice: notice
      return
    end

    @integration.save!

    if @integration.access_token.present?
      ExternalLeadMigration::SetupService.call(integration: @integration) if should_validate_external_connection?(token:, webhook_listening_requested:, webhook_listening_param_present:)
      webhook_notice = sync_webhook_listening!(webhook_listening_requested) if webhook_listening_param_present
      redirect_to admin_external_lead_integration_path, notice: ["Integração de leads salva.", webhook_notice].compact.join(" ")
    else
      redirect_to admin_external_lead_integration_path, notice: "Configuração da integração salva."
    end
  rescue => e
    @integration.mark_failed!(e.message) if @integration&.persisted?
    redirect_to admin_external_lead_integration_path, alert: "Falha ao salvar integração de leads: #{e.message}"
  end

  def test_connection
    ensure_token!
    ExternalLeadMigration::SetupService.call(integration: @integration)
    redirect_to admin_external_lead_integration_path, notice: "Conexão externa validada."
  rescue => e
    @integration.mark_failed!(e.message) if @integration&.persisted?
    redirect_to admin_external_lead_integration_path, alert: "Falha ao validar integração externa: #{e.message}"
  end

  def subscribe
    ensure_token!
    ensure_connected!
    hook_url = external_lead_webhook_url
    ExternalLeadMigration::WebhookSubscriptionService.subscribe!(integration: @integration, hook_url:)
    redirect_to admin_external_lead_integration_path, notice: "Webhooks externos assinados para criação, atualização e fechamento."
  rescue => e
    @integration.mark_failed!(e.message) if @integration&.persisted?
    redirect_to admin_external_lead_integration_path, alert: "Falha ao assinar webhooks externos: #{e.message}"
  end

  def backfill
    ensure_connected!
    @integration.update!(
      sync_status: "processing",
      sync_message: "Importação histórica enfileirada.",
      imported_count: 0,
      updated_count: 0,
      failed_count: 0,
      current_page: 0
    )
    ExternalLeadMigration::BackfillLeadsJob.perform_later(@integration.id)
    redirect_to admin_external_lead_integration_path, notice: "Importação histórica iniciada em segundo plano."
  rescue => e
    redirect_to admin_external_lead_integration_path, alert: "Falha ao iniciar importação histórica: #{e.message}"
  end

  def sync_now
    ensure_connected!
    ExternalLeadMigration::IncrementalSyncJob.perform_later(@integration.id)
    redirect_to admin_external_lead_integration_path, notice: "Sincronização incremental externa enfileirada."
  rescue => e
    redirect_to admin_external_lead_integration_path, alert: "Falha ao iniciar sincronização externa: #{e.message}"
  end

  def deactivate
    ensure_token!
    ExternalLeadMigration::WebhookSubscriptionService.unsubscribe!(integration: @integration)
    redirect_to admin_external_lead_integration_path, notice: "Integração de leads inativada."
  rescue => e
    @integration.update(enabled: false, status: "inactive", webhook_listening_enabled: false, deactivated_at: Time.current, last_error_message: e.message)
    redirect_to admin_external_lead_integration_path, alert: "Integração local inativada, mas houve falha ao cancelar o webhook externo: #{e.message}"
  end

  private

  def load_integration
    @integration = ExternalLeadIntegration.current(current_tenant)
  end

  def external_lead_params
    params.require(:external_lead_integration).permit(
      :enabled,
      :access_token,
      :webhook_listening_enabled,
      :accept_lead_without_phone,
      operational_stage_mappings: [:key, :stage_id],
      operational_stage_targets: [:stage_id, { keys: [] }]
    )
  end

  def extract_enabled_request(attrs)
    return @integration.enabled? unless attrs.key?("enabled")

    ActiveModel::Type::Boolean.new.cast(attrs["enabled"])
  end

  def extract_webhook_listening_request!(attrs)
    return @integration.webhook_listening_enabled? unless attrs.key?("webhook_listening_enabled")

    ActiveModel::Type::Boolean.new.cast(attrs.delete("webhook_listening_enabled"))
  end

  def sync_webhook_listening!(requested)
    if requested
      ensure_connected!
      hook_url = external_lead_webhook_url
      if @integration.webhook_subscription_active?(hook_url)
        return "Escuta de novos leads já estava ativa."
      end

      ExternalLeadMigration::WebhookSubscriptionService.subscribe!(integration: @integration, hook_url:)
      "Escuta de novos leads habilitada."
    elsif @integration.subscribed_at.present? || @integration.webhook_url.present? || @integration.webhook_listening_enabled?
      unsubscribe_webhook_best_effort
    end
  end

  def should_validate_external_connection?(token:, webhook_listening_requested:, webhook_listening_param_present:)
    token.present? || (webhook_listening_param_present && webhook_listening_requested)
  end

  def unsubscribe_webhook_best_effort
    @integration.update!(
      webhook_listening_enabled: false,
      webhook_url: nil,
      subscribed_at: nil,
      unsubscribed_at: Time.current,
      sync_message: "Escuta de novos leads desativada localmente.",
      last_error_message: nil
    )

    begin
      ExternalLeadMigration::WebhookSubscriptionService.unsubscribe!(integration: @integration, deactivate: false)
      "Escuta de novos leads desativada."
    rescue => e
      @integration.update(last_error_message: e.message)
      "Escuta de novos leads desativada localmente. Houve falha ao cancelar o webhook externo: #{e.message}"
    end
  end

  def deactivate_integration_locally!
    had_external_subscription = @integration.subscribed_at.present? || @integration.webhook_url.present? || @integration.webhook_listening_enabled?
    @integration.assign_attributes(
      enabled: false,
      status: "inactive",
      webhook_listening_enabled: false,
      webhook_url: nil,
      subscribed_at: nil,
      unsubscribed_at: Time.current,
      deactivated_at: Time.current,
      sync_message: "Integração externa inativada localmente.",
      last_error_message: nil
    )
    @integration.save!

    return "Integração de leads inativada." unless had_external_subscription && @integration.access_token.present?

    begin
      ExternalLeadMigration::WebhookSubscriptionService.unsubscribe!(integration: @integration, deactivate: false)
      "Integração de leads inativada e escuta externa cancelada."
    rescue => e
      @integration.update(last_error_message: e.message)
      "Integração de leads inativada localmente. Houve falha ao cancelar o webhook externo: #{e.message}"
    end
  end

  def external_lead_webhook_url
    host = canonical_webhook_host
    return webhooks_external_lead_url(@integration.webhook_token) if host.blank?

    webhooks_external_lead_url(@integration.webhook_token, host:, protocol: "https")
  end

  def canonical_webhook_host
    domains = current_tenant.tenant_domains.active.primary_first.pluck(:hostname)
    domains.find { |hostname| hostname.to_s.start_with?("app.") }.presence ||
      domains.first.presence
  end

  def ensure_token!
    raise "Token da API externa não configurado." if @integration.access_token.blank?
  end

  def ensure_connected!
    raise "Integração externa não conectada." unless @integration.connected?
  end

  def seller_rows
    Array(@integration.sellers_payload).map do |seller|
      seller = seller.to_h
      local_user = @integration.local_user_for_seller(seller)
      eligible = local_user.present? && (@integration.distribution_rule&.eligible_distribution_agent?(local_user) != false)
      {
        external_seller_id: seller["id"],
        name: seller["name"].presence || seller["email"].presence || "Vendedor externo",
        email: seller["email"],
        phone: seller["phone"],
        local_user:,
        eligible:
      }
    end
  end

  def operational_mapping_rows
    mappings = @integration.operational_mappings.to_h.fetch("stages", {})
    discovered = discovered_external_stage_rows
    mapped_by_stage = mappings.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(key, mapping), acc|
      acc[mapping.to_h["stage_id"].to_i] << key
    end
    suggested_by_stage = discovered.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(key, data), acc|
      next if mappings.key?(key)

      stage = uniquely_matching_stage(data[:label])
      acc[stage.id] << key if stage
    end

    current_tenant.lead_pipeline_stages.active.includes(:lead_pipeline).ordered.map do |stage|
      selected_keys = (mapped_by_stage[stage.id] + suggested_by_stage[stage.id]).uniq
      {
        stage: stage,
        selected_keys: selected_keys,
        suggested_keys: suggested_by_stage[stage.id],
        sample_count: selected_keys.sum { |key| discovered.dig(key, :count).to_i }
      }
    end
  end

  def external_stage_options
    mappings = @integration.operational_mappings.to_h.fetch("stages", {})
    discovered = discovered_external_stage_rows
    keys = (discovered.keys + mappings.keys).uniq

    keys.map do |key|
      label = discovered.dig(key, :label).presence || key.to_s.tr("_", " ").humanize
      count = discovered.dig(key, :count).to_i
      option_label = count.positive? ? "#{label} (#{count})" : label
      [option_label, key]
    end.sort_by { |label, _key| label.to_s.downcase }
  end

  def discovered_external_stage_rows
    return {} unless @integration.persisted?

    current_tenant.leads
                  .where(external_lead_integration: @integration)
                  .order(external_last_synced_at: :desc, updated_at: :desc)
                  .limit(250)
                  .pluck(:other_information)
                  .each_with_object({}) do |info, acc|
      payload = info.to_h["external_lead_payload"].presence || info
      mapper = ExternalLeadMigration::LeadMapper.new(payload)
      key = mapper.external_status_key
      next if key.blank?

      acc[key] ||= { label: mapper.external_status_name, count: 0 }
      acc[key][:count] += 1
    end
  end

  def uniquely_matching_stage(label)
    normalized = LeadPipelineStage.normalized_name_key(label)
    matches = current_tenant.lead_pipeline_stages.active.select do |stage|
      LeadPipelineStage.normalized_name_key(stage.name) == normalized
    end
    matches.one? ? matches.first : nil
  end
end
