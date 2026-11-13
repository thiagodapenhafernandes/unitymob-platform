module ExternalLeadMigration
  class ExportLeadJob < ApplicationJob
    queue_as :sync

    class InvalidResponse < StandardError; end
    EXPORT_LOCK_NAMESPACE = 72420

    retry_on ExternalLeadMigration::Client::Error, wait: :polynomially_longer, attempts: 5

    def perform(lead_id, tenant_id:)
      tenant = Tenant.find_by(id: tenant_id)
      return unless tenant

      lead = tenant.leads.find_by(id: lead_id)
      return unless lead

      # Serializa apenas as exportações, sem manter transação/lock do cadastro durante HTTP.
      Lead.connection_pool.with_connection do |connection|
        locked = connection.select_value("SELECT pg_try_advisory_lock(#{EXPORT_LOCK_NAMESPACE}, #{Integer(lead.id)})")
        return unless locked

        begin
          export!(lead.reload, tenant.external_lead_integration)
        ensure
          connection.select_value("SELECT pg_advisory_unlock(#{EXPORT_LOCK_NAMESPACE}, #{Integer(lead.id)})")
        end
      end
    rescue ExternalLeadMigration::Client::UnauthorizedError => e
      record_failure(lead, tenant, e)
    rescue StandardError => e
      record_failure(lead, tenant, e)
      raise
    end

    private

    def export!(lead, integration)
      return if lead.whatsapp_service_contact? || lead.c2s_exported_at.present? || lead.imported_from_c2s?

      rule = lead.distribution_rule
      scoped = rule&.destination_c2s?
      return if scoped && !rule.active?
      return unless scoped || integration&.export_active?
      raise Client::Error, "Integração C2S indisponível" unless integration&.connected?

      payload = LeadExportMapper.call(lead: lead)
      # shortcut: external_id correlaciona, mas não garante deduplicação remota após timeout; homologar idempotência com o C2S antes de automatizar replay desses casos.
      response = Client.new(token: integration.access_token).create_lead(payload, path: integration.export_endpoint_path)
      raise InvalidResponse, "Resposta C2S inválida" unless response.is_a?(Hash)
      external_id = response["lead_id"].presence || response["id"].presence || response.dig("data", "id").presence || response.dig("lead", "id").presence
      raise InvalidResponse, "C2S não confirmou a criação do lead" if response["success"] == false || external_id.blank?

      Lead.transaction do
        lead.update!(c2s_export_external_id: external_id, c2s_exported_at: Time.current)
        integration.increment!(:exported_count)
        integration.update_columns(last_exported_at: Time.current, last_export_error: nil, updated_at: Time.current)
        LeadActivity.log!(lead: lead, kind: "external_lead_exported", metadata: {
          external_lead_id: external_id, integration_id: integration.id
        })
      end
    end

    def record_failure(lead, tenant, error)
      tenant&.external_lead_integration&.record_export_failure!(error.message)
      LeadActivity.log!(lead: lead, kind: "external_lead_export_failed", metadata: { error_class: error.class.name }) if lead
    end
  end
end
