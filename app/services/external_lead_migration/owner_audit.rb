module ExternalLeadMigration
  # Compara o último seller recebido com a atribuição local sem propor sobrescrita automática.
  class OwnerAudit
    def initialize(integration:)
      @integration = integration
      @seller_users = {}
    end

    def each_difference
      return enum_for(:each_difference) unless block_given?

      scope = @integration.tenant.leads
        .where("external_lead_integration_id = :id OR other_information ->> 'source' = :source",
          id: @integration.id, source: LeadMapper::PROVIDER_KEY)
        .includes(:admin_user)
      scope.find_in_batches(batch_size: 500) do |leads|
        histories = @integration.tenant.lead_activities.where(lead_id: leads.map(&:id), kind: %w[distributed accepted])
          .order(:created_at, :id).group_by(&:lead_id)
        leads.each do |lead|
          info = lead.other_information.to_h
          seller = info["external_lead_seller"].presence || info.dig("external_lead_payload", "attributes", "seller") || {}
          seller_user = @seller_users.fetch(seller.to_json) { @seller_users[seller.to_json] = @integration.local_user_for_seller(seller) }
          next if seller_user && seller_user.id == lead.admin_user_id

          history = histories.fetch(lead.id, [])
          distributions = history.select { |activity| activity.kind == "distributed" }
          yield({
            lead_id: lead.id,
            external_lead_id: lead.external_lead_id,
            local_owner: lead.admin_user&.name,
            external_owner: seller["name"],
            mapped_owner_id: seller_user&.id,
            first_received_by: distributions.first&.metadata&.dig("admin_user_name"),
            last_distributed_to: distributions.last&.metadata&.dig("admin_user_name"),
            local_acceptance: history.any? { |activity| activity.kind == "accepted" },
            operational_assignment: info["c2s_assignment_decided"] == true || distributions.any?,
            external_synced_at: info["external_lead_synced_at"],
            review: seller_user.nil? ? "seller_sem_vinculo" : (lead.admin_user_id.present? ? "preservar_responsavel_e_revisar_historico" : "revisar_lead_sem_responsavel")
          })
        end
      end
    end
  end
end
