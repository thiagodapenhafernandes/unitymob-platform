module Habitations
  class DestroyReferences
    def self.call(habitation:)
      raise ArgumentError, "Imóvel persistido e conta obrigatórios" unless habitation.persisted? && habitation.tenant_id.present?

      [AiPropertyShareItem, HabitationPhotoShare, LeadPropertyInterest].each do |model|
        reference_scope(model, :habitation_id, habitation).find_each(&:destroy!)
      end

      [
        [AiPropertySearchHistory, :selected_habitation_id],
        [AiPropertyShareAuditEvent, :habitation_id],
        [Appointment, :habitation_id],
        [ClientInteraction, :habitation_id],
        [ClientPropertyInterest, :habitation_id],
        [CrmAppointment, :habitation_id],
        [OperationalUserEvent, :habitation_id],
        [PortalIntegrationEvent, :habitation_id],
        [PortalListingState, :habitation_id],
        [Proposal, :habitation_id],
        [PublicNavigationEvent, :habitation_id],
        [SeoConversionEvent, :habitation_id],
        [VistaFileAsset, :habitation_id]
      ].each do |model, column|
        attributes = { column => nil }
        attributes[:updated_at] = Time.current if model.column_names.include?("updated_at")
        reference_scope(model, column, habitation).update_all(attributes)
      end
    end

    def self.reference_scope(model, column, habitation)
      scope = model.where(column => habitation.id)
      # A FK identifica a conta dos legados sem tenant; vínculos de outra conta ficam intactos.
      model.column_names.include?("tenant_id") ? scope.where(tenant_id: [habitation.tenant_id, nil]) : scope
    end
    private_class_method :reference_scope
  end
end
