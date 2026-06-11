class Admin::PortalIntegrationsController < Admin::BaseController
  before_action :require_admin!
  before_action :set_portal, only: [:update, :test_feed, :preview_feed]

  def index
    @active_portal = normalize_portal(params[:portal])
    @integrations = PortalIntegration::PORTALS.index_with { |portal| PortalIntegration.for_portal!(portal) }
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
    @listing_states = PortalListingState.where(portal: @active_portal).order(last_received_at: :desc).limit(20)
  end

  def preview_feed
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
    attrs.delete("feed_token") if attrs["feed_token"].to_s.strip.blank?
    attrs.delete("webhook_secret") if attrs["webhook_secret"].to_s.strip.blank?

    if @integration.update(attrs)
      redirect_to admin_portal_integrations_path(portal: @portal), notice: "Configuração de #{@portal_title} salva com sucesso."
    else
      redirect_to admin_portal_integrations_path(portal: @portal), alert: @integration.errors.full_messages.to_sentence
    end
  end

  def test_feed
    preview = Portal::EligibilityScope.new(@integration).preview
    @integration.update(last_feed_at: Time.current, operational_status: "tested")

    redirect_to admin_portal_integrations_path(portal: @portal), notice: "Teste de feed concluído: elegíveis=#{preview[:eligible_count]}, rejeitados=#{preview[:rejected_count]}."
  end

  private

  def set_portal
    @portal = normalize_portal(params[:portal])
    @portal_title = PortalIntegration::PORTAL_DEFINITIONS.dig(@portal, :title) || @portal.titleize
    @integration = PortalIntegration.for_portal!(@portal)
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_portal_integrations_path, alert: "Portal inválido."
  end

  def portal_params
    params.require(:portal_integration).permit(
      :enabled,
      :require_exibir_no_site,
      :feed_token,
      :account_id,
      :publisher_id,
      :webhook_secret,
      allowed_statuses: [],
      allowed_business_types: []
    )
  end

  def normalize_portal(value)
    portal = value.to_s.downcase
    return PortalIntegration::PORTALS.first unless PortalIntegration::PORTALS.include?(portal)

    portal
  end
end
