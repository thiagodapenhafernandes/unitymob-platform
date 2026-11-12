module ExternalLeadMigration
  class MirrorSeller
    def self.call(integration:, seller:)
      seller = seller.to_h.stringify_keys
      return if seller["id"].blank?

      integration.with_lock do
        raise ArgumentError, "Espelhamento contínuo desativado" unless integration.mirror_c2s_owners?

        user = integration.local_user_for_seller(seller)
        user = nil if user&.super_admin?
        unless user
          email = integration.mirror_seller_reference_email(seller['id'])
          user = integration.tenant.admin_users.account_members.find_by(email: email) ||
            integration.tenant.admin_users.create!(
              name: seller["name"].presence || "Corretor C2S",
              email: email, password: SecureRandom.hex(32), active: false,
              role: :editor, acting_type: :both
            )
        end
        if !user.active? && user.email == integration.mirror_seller_reference_email(seller["id"]) &&
            seller["name"].present? && user.name != seller["name"]
          user.update!(name: seller["name"])
        end
        if integration.seller_mappings[seller["id"].to_s].to_i != user.id
          integration.update!(seller_mappings: integration.seller_mappings.merge(seller["id"].to_s => user.id))
        end
        user
      end
    end
  end
end
