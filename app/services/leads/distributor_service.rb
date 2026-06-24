module Leads
  class DistributorService
    def self.find_and_distribute(lead)
      new(lead).distribute
    end

    def initialize(lead)
      @lead = lead
    end

    def distribute
      rule = find_matching_rule
      return nil unless rule

      if rule.represamento_active? && inside_holding_hours?(rule)
        @lead.update(admin_user_id: nil, status: :represado, distribution_rule_id: rule.id)
        @lead.activities.create(kind: "dammed", metadata: { rule_id: rule.id, rule_name: rule.name })
        return rule
      end

      if rule.shark_tank?
        @lead.update(
          admin_user_id: nil,
          status: :aguardando_aceite,
          distribution_rule_id: rule.id
        )
        @lead.activities.create(kind: "shark_tank_ready", metadata: { rule_id: rule.id, rule_name: rule.name })
        # Notifica TODOS os corretores da regra; o 1º que aceitar vira dono.
        Leads::NotificationDispatcher.notify_shark_tank(@lead.reload, rule)
        return rule
      end

      candidates = rule.candidates_filtered_by_checkin
      if rule.require_active_checkin? && candidates.empty?
        return dammed_no_eligible_checkin(rule) if rule.represamento_active?
        return nil
      end

      # Fidelização: pessoa já atendida volta para o mesmo corretor (config global
      # em LeadSetting). Só quando elegível; senão segue a distribuição normal.
      sticky_user = Leads::StickyAssignment.corretor_for(@lead, rule, candidates: candidates)
      if sticky_user
        finalize_assignment(rule, admin_user_id: sticky_user.id, admin_user_name: sticky_user.name, sticky: true)
        return rule
      end

      agent = rule.next_available_agent(candidates)
      return nil unless agent

      finalize_assignment(rule, admin_user_id: agent.admin_user_id, admin_user_name: agent.admin_user&.name)
      rule.rotate_queue!(agent.admin_user_id)

      rule
    rescue => e
      Rails.logger.error "[DistributorService] Erro ao distribuir lead #{@lead.id}: #{e.message}"
      nil
    end

    private

    # Atribui o lead ao corretor, registra a atividade, agenda o pocket e dispara
    # as notificações. Reutilizado pela fidelização e pela distribuição normal.
    def finalize_assignment(rule, admin_user_id:, admin_user_name:, sticky: false)
      @lead.update(admin_user_id: admin_user_id, status: :waiting_acceptance, distribution_rule_id: rule.id)

      metadata = {
        rule_id: rule.id,
        rule_name: rule.name,
        admin_user_id: admin_user_id,
        admin_user_name: admin_user_name
      }
      metadata[:sticky] = true if sticky
      @lead.activities.create(kind: "distributed", metadata: metadata)

      if rule.pocket_active? && rule.pocket_time.to_i > 0
        Leads::PocketExpirationJob.set(wait: rule.pocket_time.to_i.minutes).perform_later(@lead.id)
      end

      # Dispara notificações conforme as flags da regra (push/whatsapp/email/webhook)
      begin
        Leads::NotificationDispatcher.deliver(@lead.reload, sticky: sticky)
      rescue => e
        Rails.logger.warn("[DistributorService] notificação falhou pro lead #{@lead.id}: #{e.message}")
      end
    end

    def dammed_no_eligible_checkin(rule)
      @lead.update(admin_user_id: nil, status: :represado, distribution_rule_id: rule.id)
      @lead.activities.create(kind: "dammed", metadata: {
        rule_id: rule.id,
        rule_name: rule.name,
        reason: "no_eligible_agent_with_checkin"
      })
      rule
    end

    def find_matching_rule
      DistributionRule.active.find_each do |rule|
        begin
          if matches_source?(rule) && matches_business_type?(rule) && matches_filters?(rule)
            return rule
          end
        rescue => e
          Rails.logger.error "[DistributorService] Erro ao verificar regra #{rule.id}: #{e.message}"
          next
        end
      end
      nil
    end

    def matches_filters?(rule)
      return false unless matches_webhook_tags?(rule)

      if rule.min_price.present?
         lead_value = @lead.respond_to?(:value) ? @lead.value.to_f : 0.0
         return false if lead_value < rule.min_price
      end

      if rule.max_price.present?
         lead_value = @lead.respond_to?(:value) ? @lead.value.to_f : 0.0
         return false if lead_value > rule.max_price
      end

      if rule.custom_filters.present? && rule.custom_filters.is_a?(Array)
        rule.custom_filters.each do |filter|
          next unless filter["key"].present? && filter["value"].present?
          key = filter["key"]
          val_rule = filter["value"].to_s.downcase.strip
          val_lead = get_lead_value(key).to_s.downcase.strip
          return false unless val_lead.include?(val_rule)
        end
      end
      true
    end

    def matches_webhook_tags?(rule)
      return true unless rule.source_webhook? && @lead.origin.to_s.downcase == "webhook"

      expected_tags = Array(rule.webhook_tags).map { |tag| normalize_tag(tag) }.reject(&:blank?)
      return true if expected_tags.blank?

      lead_tags = webhook_tags_for_lead
      (expected_tags & lead_tags).any?
    end

    def webhook_tags_for_lead
      info = @lead.other_information.is_a?(Hash) ? @lead.other_information : {}
      values = [
        info["webhook_tags"],
        info["keywords"],
        info["tags"]
      ]

      values
        .flat_map { |value| Array.wrap(value) }
        .flat_map { |value| value.to_s.split(",") }
        .map { |tag| normalize_tag(tag) }
        .reject(&:blank?)
        .uniq
    end

    def normalize_tag(tag)
      tag.to_s.strip.downcase
    end

    def get_lead_value(key)
      if @lead.respond_to?(key) && @lead.send(key).present?
        @lead.send(key)
      elsif @lead.respond_to?(:answer_for) && @lead.answer_for(key).present?
        @lead.answer_for(key)
      elsif @lead.other_information.is_a?(Hash) && @lead.other_information.key?(key)
        @lead.other_information[key]
      else
        ""
      end
    end

    def matches_source?(rule)
      origin = @lead.origin.to_s.downcase

      if rule.source_meta? && (origin.include?("facebook") || origin.include?("instagram") || origin.include?("meta"))
        return true
      end

      if rule.source_portal? && (origin.include?("zap") || origin.include?("vivareal") || origin.include?("olx"))
        return true
      end

      if rule.source_webhook? && origin == "webhook"
        return true
      end

      # Default to site if it doesn't match other specific sources and rule allows site
      # Simplified site match logic
      return true if !origin.include?("fb") && !origin.include?("zap") && origin != "webhook"

      false
    end

    def matches_business_type?(rule)
      return true if rule.ambos_business_type?
      lead_content = "#{@lead.product} #{@lead.origin} #{@lead.other_information}".downcase
      is_explicit_rental = lead_content.include?("aluguel") || lead_content.include?("locacao")
      is_explicit_sale = lead_content.include?("venda") || lead_content.include?("comprar")

      if rule.locacao_business_type?
        return is_explicit_rental || !is_explicit_sale
      elsif rule.venda_business_type?
        return is_explicit_sale || !is_explicit_rental
      end
      false
    end

    def inside_holding_hours?(rule)
      return false unless rule.represamento_active?
      schedule = rule.represamento_schedule
      return false if schedule.blank?

      now = Time.zone.now
      current_day_key = now.strftime("%a").downcase
      day_config = schedule[current_day_key]
      return false unless day_config && day_config["active"] == "true"

      start_time = Time.zone.parse("#{now.to_date} #{day_config["start"]}")
      end_time = Time.zone.parse("#{now.to_date} #{day_config["end"]}")

      if start_time <= end_time
         now < start_time || now > end_time
      else
         now > end_time && now < start_time
      end
    rescue
      false
    end
  end
end
