class PortalLeadProcessingJob < ApplicationJob
  queue_as :default

  # Erros transitórios (banco, rede) estouram para o retry; após esgotar, o
  # job cai em failed_executions do SolidQueue (visível no Mission Control).
  # Descartes permanentes (payload inválido, imóvel desconhecido/ambíguo,
  # recebimento desligado, sem telefone) viram evento de quarentena com
  # retorno — nunca exceção, pois retry não os resolve.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(payload, integration_id = nil)
    lead = Portal::GrupozapLead.call(payload)
    if lead.nil?
      Rails.logger.warn "[PortalLeadProcessingJob] Payload sem originLeadId — descartado."
      return
    end

    integration = PortalIntegration.find_by(id: integration_id) if integration_id
    return quarantine(lead, tenant: nil, reason: "invalid_integration") if integration_id && !integration&.grupozap_family?
    property, resolution = resolve_property(lead, integration: integration)
    if property.nil?
      return quarantine(lead, tenant: nil, reason: resolution[:reason], tenant_ids: resolution[:tenant_ids])
    end

    tenant = property.tenant
    unless integration ? integration.enabled? && integration.leads_enabled? : receiving?(tenant)
      return quarantine(lead, tenant: tenant, reason: "leads_disabled")
    end

    Current.set(tenant: tenant) do
      if tenant.leads.where("other_information ->> 'portal_lead_id' = ?", lead[:origin_lead_id]).exists?
        Rails.logger.info "[PortalLeadProcessingJob] Lead #{lead[:origin_lead_id]} já existe no tenant #{tenant.id} — ignorado."
        return
      end

      if lead[:phone].blank?
        return quarantine(lead, tenant: tenant, reason: "missing_phone")
      end

      created = create_lead!(tenant, property, lead)
      touch_integrations(tenant) if created
    end
  end

  private

  def resolve_property(lead, integration: nil)
    if lead[:listing_code].blank?
      return [nil, { reason: lead[:mcmv].present? ? "mcmv_no_listing" : "missing_listing" }]
    end

    scope = integration ? Habitation.where(tenant_id: integration.tenant_id) : Habitation.all
    matches = scope.where(codigo: lead[:listing_code]).includes(:tenant).to_a
    tenants = matches.map(&:tenant).compact.uniq
    return [matches.first, {}] if tenants.one?
    return [nil, { reason: "unknown_listing" }] if tenants.empty?

    [nil, { reason: "ambiguous_listing", tenant_ids: tenants.map(&:id) }]
  end

  def receiving?(tenant)
    PortalIntegration.where(
      tenant: tenant,
      portal: PortalIntegration::LEGACY_GRUPOZAP_PORTALS,
      enabled: true,
      leads_enabled: true
    ).exists?
  end

  def create_lead!(tenant, property, lead)
    record = Leads::Intake.create!(tenant: tenant,
      # NÃO pré-atribuir corretor: route_lead distribui pelas regras normais.
      name: lead[:name].presence || "Lead Grupo OLX",
      email: lead[:email],
      phone: lead[:phone],
      client_name: lead[:name],
      client_email: lead[:email],
      client_phone: lead[:phone],
      origin: Portal::GrupozapLead::ORIGIN,
      attribution_channel: Portal::GrupozapLead::CHANNEL,
      attribution_source: "grupozap",
      attribution_data: {
        "lead_origin" => lead[:lead_origin],
        "lead_type" => lead[:lead_type],
        "transaction_type" => lead[:transaction_type],
        "origin_listing_id" => lead[:origin_listing_id]
      },
      product: property.display_title,
      property_id: property.id,
      custom_answers: {},
      other_information: lead[:raw].as_json.merge(
        "portal_lead_id" => lead[:origin_lead_id],
        "portal_temperature" => lead[:temperature],
        "portal_message" => lead[:message],
        "processed_at" => Time.current
      )
    )
    if record.destroyed? && record.complemented_into_id.present?
      Rails.logger.info "[PortalLeadProcessingJob] Lead #{lead[:origin_lead_id]} agregada ao lead #{record.complemented_into_id} (tenant #{tenant.id})."
      return :complemented
    end
    record.property_interests.find_or_create_by!(habitation: property) { |interest| interest.tenant = tenant }
    Rails.logger.info "[PortalLeadProcessingJob] Lead #{lead[:origin_lead_id]} criado no tenant #{tenant.id} (lead #{record.id})."
  rescue ActiveRecord::RecordNotUnique
    nil
  rescue ActiveRecord::RecordInvalid => e
    # Dados inválidos são permanentes: quarentena com motivo, sem retry.
    quarantine(lead, tenant: tenant, reason: "invalid_lead")
    Rails.logger.warn "[PortalLeadProcessingJob] Lead #{lead[:origin_lead_id]} inválido: #{e.record.errors.full_messages.to_sentence}"
    nil
  end

  def touch_integrations(tenant)
    now = Time.current
    PortalIntegration.where(
      tenant: tenant,
      portal: PortalIntegration::LEGACY_GRUPOZAP_PORTALS,
      enabled: true,
      leads_enabled: true
    ).update_all(last_lead_at: now, operational_status: "lead_received", updated_at: now)
  end

  # Quarentena: rastro operacional no banco (nunca exceção). O portal exige
  # um valor válido — usa a primeira integração OLX da conta ou zapimoveis.
  def quarantine(lead, tenant:, reason:, tenant_ids: nil)
    portal = tenant_portal_for(tenant)
    Rails.logger.warn "[PortalLeadProcessingJob] Lead #{lead[:origin_lead_id]} em quarentena (#{reason})."
    event_attributes = {
      portal: portal,
      tenant: tenant,
      habitation_code: lead[:listing_code],
      external_listing_id: lead[:origin_listing_id],
      event_type: "lead_quarantined",
      normalized_status: reason,
      received_at: Time.current,
      raw_payload: {
        "reason" => reason,
        "origin_lead_id" => lead[:origin_lead_id],
        "tenant_ids" => tenant_ids
      }.compact
    }
    # Contexto explícito: sem conta dona o evento fica sem tenant (nunca
    # herda o ambiente, que seria atribuição falsa).
    Current.set(tenant: tenant) { PortalIntegrationEvent.create!(event_attributes) }
    true
  end

  def tenant_portal_for(tenant)
    if tenant.present?
      found = PortalIntegration.where(tenant: tenant, portal: PortalIntegration::LEGACY_GRUPOZAP_PORTALS)
                               .order(:portal).pick(:portal)
      return found if found.present?
    end
    "zapimoveis"
  end
end
