module Instagram
  class InternalSender
    def self.exclude_from_leads(scope, tenant:)
      matching_members = tenant.admin_users.account_members.active.where.not(instagram_username: nil)
        .where("admin_users.instagram_direct_ids ->> leads.instagram_account_id = leads.instagram_scoped_id")
        .select(1)
      scope.where("NOT EXISTS (?)", matching_members)
    end

    def self.match?(tenant:, page:, sender_id:)
      members = tenant.admin_users.account_members.active.where.not(instagram_username: nil)
      return false unless members.exists?
      return true if members.where("instagram_direct_ids ->> ? = ?", page.instagram_id, sender_id).exists?
      return false if page.access_token.blank?

      profile = Koala::Facebook::API.new(page.access_token).get_object(sender_id, fields: "username")
      username = profile["username"].to_s.downcase.presence
      return false unless username

      member = members.find_by(instagram_username: username)
      return false unless member

      member.with_lock do
        next false unless member.active? && !member.super_admin? && member.tenant_id == tenant.id && member.instagram_username == username

        verified_id = member.instagram_direct_ids[page.instagram_id]
        next false if verified_id.present? && verified_id != sender_id

        member.update_columns(instagram_direct_ids: member.instagram_direct_ids.merge(page.instagram_id => sender_id)) unless verified_id
        true
      end
    rescue Koala::Facebook::APIError, Faraday::Error, Timeout::Error, SocketError
      Rails.logger.warn("[Instagram Direct] consulta de identidade interna indisponível tenant_id=#{tenant.id}")
      false
    end
  end
end
