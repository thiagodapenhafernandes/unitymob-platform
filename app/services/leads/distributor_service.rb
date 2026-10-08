module Leads
  class DistributorService
    def self.find_and_distribute(lead)
      new(lead).distribute
    end

    def self.distribute_to(lead, rule)
      new(lead).distribute_to(rule)
    end

    def self.distribute_to_agent(lead, rule, admin_user)
      new(lead).distribute_to_agent(rule, admin_user)
    end

    def self.redistribute(lead, inquiry:, rule: nil)
      new(lead, inquiry: inquiry).redistribute(rule)
    end

    def initialize(lead, inquiry: nil)
      @lead = lead
      @inquiry = inquiry
    end

    def redistribute(rule = nil)
      rule ||= find_matching_rule
      return distribute_to(rule) if rule&.active?

      # Sem regra, não abandona um atendimento ativo; entradas encerradas ficam visíveis para triagem.
      keep_owner = operational? && @lead.admin_user&.active?
      unless keep_owner
        prepare_reentry!
        @lead.save!
        return true if rule && ContingencyService.try_forward!(@lead, rule: rule, reason: "deactivated")
        return true if rule.nil? && ContingencyService.default!(@lead)
      end
      LeadActivity.log!(lead: @lead, kind: "distribution_failed", metadata: {
        reason: "no_matching_rule", inquiry_origin: @inquiry.origin, rule_id: rule&.id
      }.compact)
      keep_owner ? :kept : nil
    end

    def distribute
      complemented = try_complement
      return complemented if complemented

      rule = find_matching_rule
      unless rule
        forwarded = ContingencyService.default!(@lead)
        LeadActivity.log!(lead: @lead, kind: "distribution_failed", metadata: { reason: "no_matching_rule" }) unless forwarded
        return forwarded
      end

      distribute_to(rule)
    end

    def distribute_to(rule)
      return nil unless rule
      raise ArgumentError, "Regra de distribuição pertence a outro tenant" if rule.tenant_id != tenant.id
      if !@inquiry && @lead.contingency_forwarded_at.present?
        rule = @lead.contingency_target_rule
        return nil unless rule&.terminal_destination_for?(tenant)
      end
      return ContingencyService.try_forward!(@lead, rule: rule, reason: "deactivated") unless rule.active?

      # Complemento: mesma pessoa com lead aberto no tempo de atendimento não
      # gera lead novo — a consulta agrega ao existente e o transitório sai.
      complemented = try_complement
      return complemented if complemented

      candidates = rule.candidates_filtered_by_checkin
      sticky_user = Leads::StickyAssignment.corretor_for(@inquiry || @lead, rule, candidates: candidates) unless @lead.contingency_forwarded_at.present? && !@inquiry
      if @inquiry && (!rule.require_active_checkin? || candidates.present?) && operational? && @lead.admin_user&.active? &&
          ((sticky_user&.id == @lead.admin_user_id) ||
            (!LeadSetting.instance(tenant: tenant).stickiness_enabled? && InquiryComplement.keeps_owner?(@lead, @inquiry)))
        return :kept
      end

      prepare_reentry!
      @lead.distribution_rule = rule
      @lead.distribution_cycle_started_at ||= Time.current
      @lead.save! if @lead.changed?

      if rule.represamento_active? && inside_holding_hours?(rule)
        return rule if ContingencyService.try_forward!(@lead, rule: rule, reason: "outside_hours")
        @lead.update!(admin_user_id: nil, status: :represado, distribution_rule_id: rule.id)
        @lead.activities.create(kind: "dammed", metadata: { rule_id: rule.id, rule_name: rule.name })
        return rule
      end

      if rule.shark_tank?
        if candidates.empty?
          return rule if ContingencyService.try_forward!(@lead, rule: rule, reason: "unavailable")
        end
        if candidates.empty? && (rule.require_active_checkin? || rule.contingency_for?("unavailable"))
          return dammed_no_eligible_checkin(rule)
        end

        @lead.update!(
          admin_user_id: nil,
          status: :aguardando_aceite,
          distribution_rule_id: rule.id
        )
        @lead.activities.create(kind: "shark_tank_ready", metadata: { rule_id: rule.id, rule_name: rule.name, participants: rule.pool_timeline_participants })
        # Notifica TODOS os corretores da regra; o 1º que aceitar vira dono.
        Leads::NotificationDispatcher.notify_shark_tank(@lead.reload, rule, candidates: candidates)
        return rule
      end

      if rule.require_active_checkin? && candidates.empty?
        return rule if ContingencyService.try_forward!(@lead, rule: rule, reason: "unavailable")
        return dammed_no_eligible_checkin(rule)
      end

      # Fidelização: pessoa já atendida volta para o mesmo corretor (config global
      # em LeadSetting). Só quando elegível; senão segue a distribuição normal.
      if sticky_user
        finalize_sticky_assignment(rule, admin_user_id: sticky_user.id, admin_user_name: sticky_user.name)
        return rule
      end

      # Seleção+rotação serializadas por regra (lock transacional curto): dois
      # leads simultâneos não elegem o mesmo corretor nem pulam o próximo da
      # fila. Nenhuma chamada externa aqui dentro — atribuição e notificações
      # ficam no finalize_assignment, fora do lock.
      agent = nil
      rule.with_rotation_lock do
        agent = rule.next_available_agent(candidates)
        rule.rotate_queue!(agent.admin_user_id) if agent
      end
      unless agent
        return rule if ContingencyService.try_forward!(@lead, rule: rule, reason: "unavailable")
        @lead.save!
        LeadActivity.log!(lead: @lead, kind: "distribution_failed", metadata: { reason: "no_eligible_agent", rule_id: rule.id })
        return nil
      end

      finalize_assignment(rule, admin_user_id: agent.admin_user_id, admin_user_name: agent.admin_user&.name)

      rule
    rescue => e
      Rails.logger.error(
        "[DistributorService] Erro ao distribuir lead #{@lead.id} " \
        "(tenant_id=#{@lead.tenant_id}, rule_id=#{rule&.id}): #{e.class}: #{e.message}"
      )
      Rails.logger.error(e.backtrace.to_a.first(5).join("\n"))
      # Registra a falha na timeline do lead (log! nunca levanta exceção):
      # consultável via SQL e visível pro gestor, em vez de evaporar no log.
      LeadActivity.log!(lead: @lead, kind: "distribution_failed", metadata: {
        error_class: e.class.name,
        error_message: e.message,
        rule_id: rule&.id,
        rule_name: rule&.name
      }.compact)
      raise if @inquiry
      nil
    end

    def distribute_to_agent(rule, admin_user)
      return nil unless rule && admin_user
      raise ArgumentError, "Regra de distribuição pertence a outro tenant" if rule.tenant_id != tenant.id
      raise ArgumentError, "Usuário pertence a outro tenant" if admin_user.tenant_id != tenant.id
      return nil unless rule.active?

      agent = rule.eligible_distribution_rule_agents.find_by(admin_user_id: admin_user.id)
      return nil unless agent

      finalize_sticky_assignment(rule, admin_user_id: admin_user.id, admin_user_name: admin_user.name)
      rule
    rescue => e
      Rails.logger.error(
        "[DistributorService] Erro ao atribuir lead #{@lead.id} para atendente " \
        "(tenant_id=#{@lead.tenant_id}, rule_id=#{rule&.id}, admin_user_id=#{admin_user&.id}): #{e.class}: #{e.message}"
      )
      LeadActivity.log!(lead: @lead, kind: "distribution_failed", metadata: {
        error_class: e.class.name,
        error_message: e.message,
        rule_id: rule&.id,
        rule_name: rule&.name,
        admin_user_id: admin_user&.id
      }.compact)
      nil
    end

    private

    def operational?
      @lead.archived_at.blank? && !Lead.non_operational_status_values(tenant: tenant).include?(@lead.status)
    end

    def prepare_reentry!
      return unless @inquiry

      @lead.skip_automatic_routing = true
      @lead.assign_attributes(admin_user: nil, status: Lead.default_status(tenant: tenant, pipeline: @lead.lead_pipeline),
        distribution_rule: nil, archived_at: nil, archived_by_admin_user: nil, archive_reason: nil, archive_note: nil,
        distribution_cycle_started_at: Time.current, contingency_forwarded_at: nil, contingency_pending: false,
        contingency_source_rule: nil, contingency_target_rule: nil, contingency_reason: nil)
    end

    def try_complement
      return nil if @inquiry || @lead.contingency_forwarded_at.present?

      target = Leads::InquiryComplement.dissolve_into_target!(@lead)
      return nil if target.nil?

      target.distribution_rule || true
    end

    # Atribui o lead ao corretor, registra a atividade, agenda o pocket e dispara
    # as notificações da distribuição normal.
    def finalize_assignment(rule, admin_user_id:, admin_user_name:)
      @lead.update!(admin_user_id: admin_user_id, status: :waiting_acceptance, distribution_rule_id: rule.id)
      rule.mark_agent_served!(admin_user_id)

      metadata = assignment_metadata(rule, admin_user_id: admin_user_id, admin_user_name: admin_user_name)
      log_assignment(rule, admin_user_id: admin_user_id, metadata: metadata)

      if rule.pocket_operational?
        Leads::PocketExpirationJob.set(wait: rule.pocket_time.to_i.minutes).perform_later(@lead.id, admin_user_id, tenant_id: @lead.tenant_id)
      end

      # Dispara notificações conforme as flags da regra (push/whatsapp/email/webhook)
      begin
        Leads::NotificationDispatcher.deliver(@lead.reload, sticky: false)
      rescue => e
        Rails.logger.warn("[DistributorService] notificação falhou pro lead #{@lead.id}: #{e.message}")
      end
    end

    def finalize_sticky_assignment(rule, admin_user_id:, admin_user_name:)
      @lead.update!(admin_user_id: admin_user_id, status: :em_atendimento, distribution_rule_id: rule.id)

      metadata = assignment_metadata(rule, admin_user_id: admin_user_id, admin_user_name: admin_user_name)
      metadata[:sticky] = true
      metadata[:direct_attendance] = true
      log_assignment(rule, admin_user_id: admin_user_id, metadata: metadata)

      begin
        Leads::NotificationDispatcher.deliver(@lead.reload, sticky: true)
      rescue => e
        Rails.logger.warn("[DistributorService] notificação falhou pro lead #{@lead.id}: #{e.message}")
      end
    end

    def assignment_metadata(rule, admin_user_id:, admin_user_name:)
      {
        rule_id: rule.id,
        rule_name: rule.name,
        admin_user_id: admin_user_id,
        admin_user_name: admin_user_name
      }
    end

    def log_assignment(rule, admin_user_id:, metadata:)
      activity = @lead.activities.create!(kind: "distributed", metadata: metadata)
      Automation::Dispatcher.dispatch(
        :lead_assigned,
        @lead,
        source: "distribution",
        payload: metadata,
        idempotency_key: "lead_assigned:#{@lead.id}:#{activity.id}"
      )
    end

    def dammed_no_eligible_checkin(rule)
      @lead.update!(admin_user_id: nil, status: :represado, distribution_rule_id: rule.id)
      @lead.activities.create(kind: "dammed", metadata: {
        rule_id: rule.id,
        rule_name: rule.name,
        reason: "no_eligible_agent_with_checkin",
        require_active_shift: rule.require_active_shift?,
        checkin_store_ids: rule.checkin_store_id_list
      })
      rule
    end

    def find_matching_rule
      tenant.distribution_rules.active.find_each do |rule|
        begin
          if matches_source?(rule) && matches_business_type?(rule) && matches_filters?(rule)
            return rule
          end
        rescue => e
          Rails.logger.error "[DistributorService] Erro ao verificar regra #{rule.id}: #{e.class}: #{e.message}"
          raise if @inquiry
          next
        end
      end
      nil
    end

    def tenant
      @tenant ||= @lead.tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para distribuir lead" if @tenant.blank?

      @tenant
    end

    def routing_lead
      @inquiry || @lead
    end

    def matches_filters?(rule)
      return false unless matches_webhook_tags?(rule)
      return false unless matches_meta_scope?(rule)
      return false unless matches_tiktok_scope?(rule)
      return false unless matches_linkedin_scope?(rule)

      if rule.min_price.present?
         lead_value = routing_lead.respond_to?(:value) ? routing_lead.value.to_f : 0.0
         return false if lead_value < rule.min_price
      end

      if rule.max_price.present?
         lead_value = routing_lead.respond_to?(:value) ? routing_lead.value.to_f : 0.0
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

    def matches_tiktok_scope?(rule)
      return true unless routing_lead.attribution_channel == "tiktok_ads"
      integration = @tiktok_integration ||= TiktokIntegration.find_by(tenant: tenant)
      info = routing_lead.other_information.to_h
      return false unless integration&.connected? && integration.selected_account_ids.include?(info["tiktok_advertiser_id"].to_s)
      accounts = Array(rule.tiktok_account_ids).compact_blank
      forms = Array(rule.tiktok_form_ids).compact_blank
      (accounts.empty? || accounts.include?(info["tiktok_advertiser_id"].to_s)) &&
        (forms.empty? || forms.include?(info["tiktok_form_id"].to_s))
    end

    def matches_linkedin_scope?(rule)
      return true unless rule.source_linkedin? && routing_lead.attribution_channel == "linkedin_ads"

      integration = @linkedin_integration ||= LinkedinIntegration.find_by(tenant: tenant)
      return false unless integration&.connected?
      info = routing_lead.other_information || {}
      return false unless integration.selected_account_ids.include?(info["linkedin_account_id"].to_s)
      campaigns = Array(rule.linkedin_campaign_ids).compact_blank
      forms = Array(rule.linkedin_form_ids).compact_blank
      (campaigns.empty? || campaigns.include?(info["linkedin_campaign_id"].to_s)) &&
        (forms.empty? || forms.include?(info["linkedin_form_id"].to_s))
    end

    # Regra Meta com páginas/formulários selecionados só aceita leads DAQUELA
    # página/formulário (lead carrega meta_page_id/meta_form_id no
    # other_information). Vazio = aceita qualquer origem Meta (documentado na
    # UI). Fail-closed: lead meta sem identificação de página não casa com
    # regra que filtra páginas.
    def matches_meta_scope?(rule)
      return true unless rule.source_meta? && meta_origin?(routing_lead.origin.to_s.downcase)

      page_ids = Array(rule.meta_page_ids).compact_blank.map(&:to_s)
      form_ids = Array(rule.meta_forms).compact_blank.map(&:to_s)
      info = routing_lead.other_information.is_a?(Hash) ? routing_lead.other_information : {}
      if info["meta_page_id"].present?
        unless defined?(@meta_page_available)
          @meta_page_available = MetaFacebookPage.available_for_distribution(tenant.id).exists?(page_id: info["meta_page_id"].to_s)
        end
        return false unless @meta_page_available
      elsif info["meta_form_id"].present?
        unless defined?(@meta_form_available)
          pages = MetaFacebookPage.available_for_distribution(tenant.id)
          @meta_form_available = MetaLeadForm.where(meta_facebook_page_id: pages.select(:id)).exists?(form_id: info["meta_form_id"].to_s)
        end
        return false unless @meta_form_available
      end
      return true if page_ids.empty? && form_ids.empty?

      page_ok = page_ids.empty? || page_ids.include?(info["meta_page_id"].to_s)
      form_ok = form_ids.empty? || form_ids.include?(info["meta_form_id"].to_s)
      page_ok && form_ok
    end

    def matches_webhook_tags?(rule)
      return true unless rule.source_webhook? && webhook_origin?(routing_lead.origin.to_s.downcase)

      expected_tags = Array(rule.webhook_tags).map { |tag| normalize_tag(tag) }.reject(&:blank?)
      return true if expected_tags.blank?

      lead_tags = webhook_tags_for_lead
      (expected_tags & lead_tags).any?
    end

    def webhook_tags_for_lead
      info = routing_lead.other_information.is_a?(Hash) ? routing_lead.other_information : {}
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
      if routing_lead.respond_to?(key) && routing_lead.send(key).present?
        routing_lead.send(key)
      elsif routing_lead.respond_to?(:answer_for) && routing_lead.answer_for(key).present?
        routing_lead.answer_for(key)
      elsif routing_lead.other_information.is_a?(Hash) && routing_lead.other_information.key?(key)
        routing_lead.other_information[key]
      else
        ""
      end
    end

    def matches_source?(rule)
      origin = routing_lead.origin.to_s.downcase

      return rule.source_tiktok? if routing_lead.attribution_channel == "tiktok_ads"
      return true if rule.source_linkedin? && routing_lead.attribution_channel == "linkedin_ads" && routing_lead.attribution_source == "linkedin"
      return true if rule.source_meta? && meta_origin?(origin)
      return true if rule.source_rd_station? && rd_station_origin?(origin)
      return true if rule.source_lovers? && lovers_origin?(origin)
      return true if rule.source_portal? && portal_origin?(origin)
      return true if rule.source_webhook? && webhook_origin?(origin)
      return true if rule.source_site? && site_origin?(origin)

      false
    end

    def meta_origin?(origin)
      origin.include?("facebook") ||
        origin.include?("instagram") ||
        origin.include?("meta") ||
        origin.include?("fb")
    end

    def portal_origin?(origin)
      origin.include?("zap") ||
        origin.include?("vivareal") ||
        origin.include?("olx")
    end

    def rd_station_origin?(origin)
      origin.include?("rd station") || origin.include?("rdstation")
    end

    def lovers_origin?(origin)
      origin.include?("lovers") || origin.include?("leadlovers") || origin.include?("lead lovers")
    end

    def webhook_origin?(origin)
      origin == "webhook" ||
        origin == ExternalLeadMigration::LeadMapper::PROVIDER_KEY ||
        origin == ExternalLeadIntegration::LEAD_ORIGIN.downcase
    end

    def site_origin?(origin)
      origin.blank? || (!meta_origin?(origin) && !rd_station_origin?(origin) && !lovers_origin?(origin) && !portal_origin?(origin) && !webhook_origin?(origin))
    end

    def matches_business_type?(rule)
      return true if rule.ambos_business_type?
      lead_content = normalized_business_type_content
      is_explicit_rental = lead_content.match?(/\b(aluguel|alugar|locacao|locar|rent|rental)\b/)
      is_explicit_sale = lead_content.match?(/\b(venda|vender|comprar|compra|sale)\b/)

      # Regra de negócio intencional: quando o lead não traz sinal explícito de
      # venda ou locação (ex.: muitos leads Meta), regras específicas continuam
      # elegíveis. Isso preserva flexibilidade e deixa a prioridade/ordem das
      # regras decidir o destino em origens ambíguas.
      if rule.locacao_business_type?
        return is_explicit_rental || !is_explicit_sale
      elsif rule.venda_business_type?
        return is_explicit_sale || !is_explicit_rental
      end
      false
    end

    def normalized_business_type_content
      values = [
        routing_lead.product,
        routing_lead.origin,
        routing_lead.source_url,
        routing_lead.other_information,
        habitation_business_type_signal
      ]

      I18n.transliterate(values.compact.join(" ").downcase)
    end

    def habitation_business_type_signal
      habitation = routing_lead.property_id.present? ? tenant.habitations.find_by(id: routing_lead.property_id) : nil
      return "" unless habitation&.respond_to?(:whatsapp_negotiation_type)

      case habitation.whatsapp_negotiation_type
      when "rent"
        "locacao aluguel rent"
      when "sale"
        "venda comprar sale"
      when "sale_rent"
        "venda locacao sale rent"
      else
        ""
      end
    end

    def inside_holding_hours?(rule)
      rule.outside_represamento_hours?
    end
  end
end
