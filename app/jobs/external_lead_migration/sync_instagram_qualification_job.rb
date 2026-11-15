module ExternalLeadMigration
  class SyncInstagramQualificationJob < ApplicationJob
    queue_as :sync

    def perform(tenant_id, lead_id)
      tenant = Tenant.find_by(id: tenant_id)
      lead = tenant&.leads&.find_by(id: lead_id)
      return unless lead && lead.archived_at.nil?
      acquired = LeadLock.synchronize(lead.id) do
        lead.reload
        integration = tenant.external_lead_integration
        remote_id = lead.c2s_existing_id_for(integration)
        rule = lead.distribution_rule
        return unless remote_id.present? && integration&.connected? &&
          (integration.export_active? || integration.mirror_c2s_owners? || rule&.active? && rule.destination_c2s?)
        summary = Instagram::Qualification.summary(lead)
        return if summary.blank?
        digest = Digest::SHA256.hexdigest(summary)
        state = lead.other_information['instagram_c2s_qualification'].to_h
        return if state['digest'] == digest && %w[sending sent uncertain].include?(state['status'])
        checkpoint(lead, digest, 'sending')
        # shortcut: sem idempotência de append no C2S, timeout fica incerto para conciliação antes de reenviar.
        attributes = {'body' => summary}
        mode = rule&.effective_c2s_negotiation_type.presence || {'venda' => 'Compra', 'locacao' => 'Aluguel'}[lead.other_information.dig('instagram_qualification', 'business_type')]
        attributes['type_negotiation'] = {'Compra' => 0, 'Aluguel' => 1}[mode] if %w[Compra Aluguel].include?(mode)
        result = Client.new(token: integration.access_token).update_lead_routing(remote_id, attributes: attributes)
        raise Client::Error, 'C2S não confirmou a atualização' unless result.is_a?(Hash) && result['success'] == true
        checkpoint(lead, digest, 'sent')
        LeadActivity.log!(lead: lead, kind: 'note', metadata: {event: 'instagram_qualification_synced', external_lead_id: remote_id})
      rescue StandardError => error
        checkpoint(lead, digest, 'uncertain') if digest
        LeadActivity.log!(lead: lead, kind: 'note', metadata: {event: 'instagram_qualification_sync_uncertain', error_class: error.class.name})
        raise
      end
      self.class.set(wait: 10.seconds).perform_later(tenant_id, lead_id) unless acquired
    end

    private

    def checkpoint(lead, digest, status)
      lead.with_lock do
        lead.update_columns(other_information: lead.other_information.merge(
          'instagram_c2s_qualification' => {'digest' => digest, 'status' => status}))
      end
    end
  end
end
