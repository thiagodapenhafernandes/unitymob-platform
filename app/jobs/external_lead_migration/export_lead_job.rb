module ExternalLeadMigration
  class ExportLeadJob < ApplicationJob
    queue_as :sync

    retry_on ExternalLeadMigration::Client::Error, wait: :polynomially_longer, attempts: 5

    # Exporta um lead local para o C2S. Idempotente: lead já exportado sai sem
    # reenviar. Leads vindos do próprio C2S nunca voltam (anti-loop).
    def perform(lead_id, tenant_id:)
      tenant = Tenant.find_by(id: tenant_id)
      return if tenant.blank?

      lead = tenant.leads.find_by(id: lead_id)
      return if lead.blank? || lead.c2s_exported_at.present?

      integration = tenant.external_lead_integration
      return unless integration&.export_active?
      return if imported_from_c2s?(lead)

      payload = LeadExportMapper.call(lead:)
      response = ExternalLeadMigration::Client.new(token: integration.access_token)
        .create_lead(payload, path: integration.export_endpoint_path)

      external_id = response["id"].presence || response.dig("data", "id").presence || response.dig("lead", "id").presence
      lead.update!(c2s_export_external_id: external_id, c2s_exported_at: Time.current)
      integration.increment!(:exported_count)
      integration.update_columns(last_exported_at: Time.current, last_export_error: nil, updated_at: Time.current)
      LeadActivity.log!(lead:, kind: "external_lead_exported", metadata: {
        external_lead_id: external_id, integration_id: integration.id
      }.compact)
    rescue ExternalLeadMigration::Client::UnauthorizedError => e
      # Falha de credencial não se resolve com retry: registra e encerra.
      Tenant.find_by(id: tenant_id)&.external_lead_integration&.record_export_failure!(e.message)
    rescue ActiveRecord::RecordNotUnique
      # Corrida entre retries: outro worker já marcou a exportação.
      nil
    rescue ActiveRecord::RecordInvalid => e
      Tenant.find_by(id: tenant_id)&.external_lead_integration&.record_export_failure!(e.message)
    rescue StandardError => e
      Tenant.find_by(id: tenant_id)&.external_lead_integration&.record_export_failure!(e.message)
      raise
    end

    private

    def imported_from_c2s?(lead)
      return true if lead.external_lead_integration_id.present? || lead.external_lead_id.present?

      info = lead.other_information.to_h
      attribution = lead.attribution_data.to_h
      info["source"] == ExternalLeadMigration::LeadMapper::PROVIDER_KEY ||
        attribution["provider"] == ExternalLeadMigration::LeadMapper::PROVIDER_KEY ||
        Array(info["webhook_tags"]).include?(ExternalLeadIntegration::WEBHOOK_TAG)
    end
  end
end
