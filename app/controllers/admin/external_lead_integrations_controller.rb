class Admin::ExternalLeadIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }
  before_action :load_integration

  def show
    @webhook_url = @integration.persisted? ? webhooks_external_lead_url(@integration.webhook_token) : nil
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
  end

  def update
    attrs = external_lead_params.to_h
    token = attrs.delete("access_token").to_s.strip
    webhook_listening_requested = extract_webhook_listening_request!(attrs)

    @integration.assign_attributes(attrs)
    @integration.access_token = token if token.present?
    @integration.connected_by_admin_user = current_admin_user if token.present?
    raise "Token da API externa obrigatório para habilitar a escuta de novos leads." if webhook_listening_requested && @integration.access_token.blank?

    @integration.save!

    if @integration.access_token.present?
      ExternalLeadMigration::SetupService.call(integration: @integration)
      webhook_notice = sync_webhook_listening!(webhook_listening_requested)
      redirect_to admin_external_lead_integration_path, notice: ["Integração de leads salva e validada.", webhook_notice].compact.join(" ")
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
    hook_url = webhooks_external_lead_url(@integration.webhook_token)
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
    params.require(:external_lead_integration).permit(:enabled, :access_token, :webhook_listening_enabled)
  end

  def extract_webhook_listening_request!(attrs)
    return @integration.webhook_listening_enabled? unless attrs.key?("webhook_listening_enabled")

    ActiveModel::Type::Boolean.new.cast(attrs.delete("webhook_listening_enabled"))
  end

  def sync_webhook_listening!(requested)
    if requested
      ensure_connected!
      hook_url = webhooks_external_lead_url(@integration.webhook_token)
      if @integration.webhook_subscription_active?(hook_url)
        return "Escuta de novos leads já estava ativa."
      end

      ExternalLeadMigration::WebhookSubscriptionService.subscribe!(integration: @integration, hook_url:)
      "Escuta de novos leads habilitada."
    elsif @integration.subscribed_at.present? || @integration.webhook_url.present? || @integration.webhook_listening_enabled?
      ExternalLeadMigration::WebhookSubscriptionService.unsubscribe!(integration: @integration, deactivate: false)
      "Escuta de novos leads desativada."
    end
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
end
