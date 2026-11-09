module Instagram
  class ProfileEnrichmentJob < ApplicationJob
    DEFAULT_NAME = "Contato Instagram".freeze

    queue_as :sync
    retry_on Faraday::Error, Timeout::Error, wait: :polynomially_longer, attempts: 3

    def perform(tenant_id, lead_id)
      lead = Tenant.find_by(id: tenant_id)&.leads&.find_by(id: lead_id)
      return if lead.blank? || lead.instagram_scoped_id.blank? || lead.instagram_account_id.blank?

      account_id = lead.instagram_account_id
      sender_id = lead.instagram_scoped_id
      page_scope = MetaFacebookPage.available_for_distribution(tenant_id).where(instagram_id: account_id, instagram_enabled: true)
      page = page_scope.first
      return if page&.access_token.blank?

      profile = Koala::Facebook::API.new(page.access_token).get_object(sender_id, fields: "name,username")
      name = profile["name"].to_s.strip.first(255).presence
      username = profile["username"].to_s.strip[/\A[a-zA-Z0-9._]{1,30}\z/]
      return if name.blank? && username.blank?

      lead.with_lock do
        return unless lead.tenant_id == tenant_id && lead.instagram_account_id == account_id && lead.instagram_scoped_id == sender_id
        return unless page_scope.exists?(id: page.id)

        info = lead.other_information.to_h
        existing_profile = info["instagram_profile"]
        existing_profile = {} unless existing_profile.is_a?(Hash)
        if username.present? && existing_profile["username"].blank?
          lead.other_information = info.merge("instagram_profile" => existing_profile.merge("username" => username))
        end
        if lead.client_name.blank? && (lead.name.blank? || lead.name == DEFAULT_NAME || lead.name.start_with?("@"))
          lead.name = username.present? ? "@#{username}" : (name || DEFAULT_NAME)
        end
        changes = lead.changes.transform_values(&:last).slice("name", "other_information")
        # Atualizar a identificação não deve disparar webhooks comerciais do lead.
        lead.update_columns(changes) if changes.any?
      end
    rescue Koala::Facebook::APIError => error
      Rails.logger.warn("[Instagram profile] lookup refused code=#{error.fb_error_code}")
    end
  end
end
