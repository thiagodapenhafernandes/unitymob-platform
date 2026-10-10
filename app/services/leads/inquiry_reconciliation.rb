module Leads
  # Reconciliação manual de apuração não-verificada: depois que o corretor
  # confirma a identidade por fora (resposta no WhatsApp, ligação), funde a
  # apuração no lead canônico escolhido, reaproveitando o complemento de
  # consultas (interesses, contatos, atividades, rastro de auditoria).
  class InquiryReconciliation
    Error = Class.new(StandardError)

    def self.reconcile!(inquiry:, target:, actor:)
      raise Error, "apuração e destino precisam ser da mesma conta" unless inquiry.tenant_id == target.tenant_id
      raise Error, "registro não é uma apuração não-verificada" unless inquiry.unverified_inquiry?
      raise Error, "destino precisa ser outro lead" if inquiry.id == target.id
      raise Error, "destino arquivado" if target.archived_at.present?

      Lead.transaction do
        inquiry.property_interests.find_each do |interest|
          target.property_interests.find_or_create_by!(tenant: target.tenant, habitation: interest.habitation)
        end
        inquiry.activities.update_all(lead_id: target.id)
        InquiryComplement.new(inquiry).complement!(target, notify: false,
          metadata: { reconciled_by_admin_user_id: actor&.id, manual_reconciliation: true })
        inquiry.complemented_into_id = target.id
        LeadActivity.log!(lead: target, kind: "inquiry_reconciled",
          metadata: { inquiry_lead_id: inquiry.id, reconciled_by_admin_user_id: actor&.id })
        inquiry.destroy!
      end
      target
    end
  end
end
