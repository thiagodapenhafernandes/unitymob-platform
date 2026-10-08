class Admin::PortalIntegrationsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :set_portal, only: [:update, :preview_feed]

  def index
    @active_portal = normalize_portal(params[:portal])
    @integrations = PortalIntegration::PORTALS.index_with { |portal| find_integration!(portal) }
    @lead_integration = @integrations["zapimoveis"]
    @status_options = Habitation::STATUS_OPTIONS
    @business_type_options = [["Venda", "venda"], ["Aluguel", "aluguel"]]
    @previews = @integrations.transform_values { |integration| Portal::EligibilityScope.new(integration).preview }
    @readiness = @integrations.each_with_object({}) do |(portal, integration), acc|
      eligible = @previews.dig(portal, :eligible_count)
      acc[portal] = {
        status: integration.readiness_status(eligible_count: eligible),
        checklist: integration.setup_checklist(eligible_count: eligible)
      }
    end
    @listing_states = scoped_listing_states.where(portal: @active_portal).order(last_received_at: :desc).limit(20)
    @grupozap_key_configured = Setting.get(PortalIntegration::GRUPOZAP_SECRET_KEY, ENV["GRUPOZAP_SECRET_KEY"]).present?
  end

  def preview_feed
    return head(:forbidden) unless current_admin_user.system_admin?
    sample = Portal::EligibilityScope.new(@integration).eligible_scope.limit(3)

    case @integration.feed_strategy
    when "olx_xml"
      serializer = Portal::OlxXmlSerializer.new(habitations: sample, integration: @integration)
      render xml: serializer.to_xml
    when "olx_json"
      serializer = Portal::OlxJsonSerializer.new(habitations: sample, integration: @integration, portal: @portal)
      render json: serializer.as_json
    when "chaves_xml"
      serializer = Portal::ChavesXmlSerializer.new(habitations: sample, integration: @integration)
      render xml: serializer.to_xml
    when "vrsync_xml"
      serializer = Portal::VrsyncXmlSerializer.new(habitations: sample, integration: @integration)
      render xml: serializer.to_xml
    else
      render plain: "Estratégia de feed desconhecida.", status: :unprocessable_entity
    end
  end

  def update
    attrs = portal_params.to_h
    attrs.delete("webhook_secret") if attrs["webhook_secret"].to_s.strip.blank?

    if @integration.update(attrs)
      @integration.update_columns(lead_gateway_synced_at: nil) if @integration.grupozap_family? && (@integration.previous_changes.keys & %w[enabled leads_enabled]).any?
      PortalLeadGatewaySyncJob.perform_later(@integration.id) if @integration.grupozap_family?
      redirect_to admin_portal_integrations_path(portal: @portal, anchor: ("portal-leads" if params[:section] == "leads" && @integration.grupozap_family?)), notice: "Configuração de #{@portal_title} salva com sucesso."
    else
      redirect_to admin_portal_integrations_path(portal: @portal, anchor: ("portal-leads" if params[:section] == "leads" && @integration.grupozap_family?)), alert: @integration.errors.full_messages.to_sentence
    end
  end

  # Chave por CRM (vale para todos os portais OLX e contas): grava global,
  # nunca exibe o valor de volta — só o status configurada/não configurada.
  def grupozap_key
    return head(:forbidden) unless current_admin_user.system_admin?
    secret = params[:grupozap_secret_key].to_s.strip
    portal = normalize_portal(params[:portal])

    if secret.blank?
      return redirect_to admin_portal_integrations_path(portal: portal), alert: "Informe a chave enviada pelo Grupo OLX."
    end

    Setting.set(PortalIntegration::GRUPOZAP_SECRET_KEY, secret, tenant: nil)
    redirect_to admin_portal_integrations_path(portal: portal), notice: "Chave do Grupo OLX salva com sucesso."
  end

  private

  def set_portal
    @portal = normalize_portal(params[:portal])
    @portal_title = PortalIntegration::PORTAL_DEFINITIONS.dig(@portal, :title) || @portal.titleize
    @integration = find_integration!(@portal)
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_portal_integrations_path, alert: "Portal inválido."
  end

  # Resolve/cria a integração do portal SEMPRE dentro do tenant corrente, para
  # que cada conta edite apenas o seu próprio registro.
  def find_integration!(portal)
    PortalIntegration.for_portal!(portal, tenant: current_tenant).tap do |integration|
      if integration.grupozap_family? && integration.lead_route_key.blank?
        integration.with_lock do
          integration.update!(lead_route_key: SecureRandom.uuid) if integration.lead_route_key.blank?
        end
      end
    end
  end

  # Eventos/estados filtrados por tenant corrente — cada conta vê só os seus.
  # Tolerante pré-migration: sem coluna tenant_id cai no comportamento antigo.
  def scoped_listing_states
    if PortalListingState.column_names.include?("tenant_id")
      PortalListingState.where(tenant: current_tenant)
    else
      PortalListingState.none
    end
  end

  def portal_params
    support_fields = current_admin_user.system_admin? ? [:webhook_secret] : []
    params.require(:portal_integration).permit(
      :enabled,
      :require_exibir_no_site,
      :leads_enabled,
      :account_id,
      :publisher_id,
      *support_fields,
      allowed_statuses: [],
      allowed_business_types: []
    )
  end

  def normalize_portal(value)
    portal = value.to_s.downcase
    portal = "zapimoveis" if portal == "grupo_olx"
    return PortalIntegration::PORTALS.first unless PortalIntegration::PORTALS.include?(portal)

    portal
  end
end
