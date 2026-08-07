module ExternalLeadMigration
  class SetupService
    def self.call(integration:)
      new(integration:).call
    end

    def initialize(integration:)
      @integration = integration
    end

    def call
      client = Client.new(token: integration.access_token)
      company_payload = client.me
      sellers_payload = Array(client.sellers)
      tags_payload = client.tags
      ExternalLeadMigration::FunnelSync.ensure_source!(tenant: integration.tenant)
      mappings = map_sellers(sellers_payload)
      rule = ensure_support_rule!(mappings)

      integration.update!(
        enabled: true,
        status: "connected",
        distribution_rule: rule,
        company_id: company_payload["company_id"],
        company_name: company_payload["company_name"],
        company_payload: company_payload,
        sellers_payload: sellers_payload,
        tags_payload: tags_payload,
        seller_mappings: mappings,
        sync_status: "idle",
        sync_message: "Conexão externa validada. Regra de apoio atualizada.",
        last_error_message: nil
      )

      integration
    end

    private

    attr_reader :integration

    def map_sellers(sellers)
      sellers.each_with_object({}) do |seller, acc|
        seller = seller.to_h
        user = find_local_user(seller)
        acc[seller["id"].to_s] = user.id if seller["id"].present? && user
      end
    end

    def find_local_user(seller)
      email = seller["email"].to_s.strip.downcase
      if email.present?
        user = integration.tenant.admin_users.active.find_by("lower(email) = ?", email)
        return user if user
      end

      phone = Phones::Normalizer.call(seller["phone"])
      return nil if phone.blank?

      integration.tenant.admin_users.active.detect do |admin_user|
        Phones::Normalizer.call(admin_user.phone) == phone ||
          (admin_user.respond_to?(:secondary_phone) && Phones::Normalizer.call(admin_user.secondary_phone) == phone)
      end
    end

    def ensure_support_rule!(mappings)
      rule = integration.distribution_rule ||
        integration.tenant.distribution_rules.find_or_initialize_by(name: ExternalLeadIntegration::SUPPORT_RULE_NAME)

      rule.assign_attributes(
        name: ExternalLeadIntegration::SUPPORT_RULE_NAME,
        active: true,
        business_type: "ambos",
        distribution_mode: "rotary",
        source_site: false,
        source_meta: false,
        source_portal: false,
        source_webhook: true,
        webhook_tags: [ExternalLeadIntegration::WEBHOOK_TAG],
        notify_whatsapp: false,
        notify_email: false,
        notify_webhook: false,
        notify_push: true
      )
      rule.tenant = integration.tenant
      rule.save!

      sync_rule_agents!(rule, mappings.values)
      rule
    end

    def sync_rule_agents!(rule, admin_user_ids)
      selected_ids = integration.tenant.admin_users.active.where(id: admin_user_ids).select do |admin_user|
        rule.eligible_distribution_agent?(admin_user)
      end.map(&:id)
      existing = rule.distribution_rule_agents.index_by(&:admin_user_id)

      rule.transaction do
        existing.each do |admin_user_id, agent|
          agent.destroy! unless selected_ids.include?(admin_user_id)
        end

        selected_ids.each_with_index do |admin_user_id, index|
          agent = existing[admin_user_id] || rule.distribution_rule_agents.build(admin_user_id: admin_user_id)
          agent.tenant = integration.tenant if agent.respond_to?(:tenant=)
          agent.position = index + 1
          agent.weight = agent.weight.presence || 1
          agent.save!
        end
      end
    end
  end
end
