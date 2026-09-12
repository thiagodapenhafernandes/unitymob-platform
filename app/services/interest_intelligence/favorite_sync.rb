module InterestIntelligence
  # O navegador informa o estado atual; o servidor calcula as mudanças e valida o tenant.
  class FavoriteSync
    def self.property_ids_for(lead)
      ids = lead.public_navigation_sessions.where(tenant_id: lead.tenant_id).pluck(:metadata).flat_map do |metadata|
        Array(metadata.to_h["favorite_property_ids"])
      end
      Habitation.for_tenant(lead.tenant_id).where(id: ids).pluck(:id)
    end

    def self.call(session:, ids:)
      raise ArgumentError, "Conta não identificada" unless session.tenant_id
      raise ArgumentError, "Lista de favoritos inválida" unless ids.is_a?(Array) && ids.size <= 500 && ids.all? { |id| id.to_s.match?(/\A\d+\z/) }

      properties = Habitation.for_tenant(session.tenant_id).where(id: ids).index_by(&:id)
      current_ids = properties.keys.sort
      changed = false
      session.with_lock do
        previous = Array(session.metadata.to_h["favorite_property_ids"]).map(&:to_i)
        initial = !session.metadata.to_h.key?("favorite_property_ids")
        { "property_favorite_added" => current_ids - previous, "property_favorite_removed" => previous - current_ids }.each do |name, changed_ids|
          Habitation.for_tenant(session.tenant_id).where(id: changed_ids).each do |property|
            session.events.create!(
              tenant_id: session.tenant_id, lead_id: session.lead_id, habitation: property,
              name: name, occurred_at: Time.current,
              metadata: { property_title: property.display_title, initially_observed: initial },
              property_snapshot: { codigo: property.codigo }
            )
            changed = true
          end
        end
        if initial || previous.sort != current_ids
          session.update!(metadata: session.metadata.to_h.merge("favorite_property_ids" => current_ids, "favorites_observed_at" => Time.current.iso8601))
        end
      end
      changed
    end
  end
end
