module Leads
  # Fidelização (lead stickiness): se a pessoa do lead já foi atendida por um
  # corretor, devolve esse corretor para a distribuição, respeitando a config
  # global em LeadSetting (chave de match, dono anterior, fallback e janela).
  # Retorna nil quando desligado, sem match ou corretor inelegível.
  class StickyAssignment
    def self.corretor_for(lead, rule, candidates:)
      new(lead, rule, candidates).corretor
    end

    def initialize(lead, rule, candidates)
      @lead = lead
      @rule = rule
      @candidates = candidates
      @setting = LeadSetting.instance
    end

    def corretor
      return nil unless @setting.stickiness_enabled?

      owner_id = previous_owner_id
      return nil if owner_id.blank?

      user = @lead.tenant.admin_users.find_by(id: owner_id)
      return nil unless eligible?(user)

      user
    end

    private

    def previous_owner_id
      scope = base_scope
      return nil if scope.nil?

      scope.reorder(updated_at: :desc).limit(1).pick(:admin_user_id)
    end

    # Leads anteriores (não o atual) com corretor atribuído, aplicando match,
    # dono (atendido x qualquer atribuição) e janela de tempo.
    def base_scope
      scope = @lead.tenant.leads.where.not(id: @lead.id).where.not(admin_user_id: nil)

      scope = apply_match(scope)
      return nil if scope.nil?

      scope = scope.where(status: @setting.attended_status_values) if @setting.owner_attended_only?
      scope = scope.where("leads.updated_at >= ?", @setting.stickiness_window_days.to_i.days.ago) unless @setting.window_forever?
      scope
    end

    def apply_match(scope)
      phones = phone_variants
      emails = email_variants

      case @setting.stickiness_match
      when "phone_and_email"
        return nil if phones.blank? || emails.blank?
        scope.where(phone_sql, phones: phones).where(email_sql, emails: emails)
      when "phone_or_email"
        return nil if phones.blank? && emails.blank?
        if phones.present? && emails.present?
          scope.where("(#{phone_sql}) OR (#{email_sql})", phones: phones, emails: emails)
        elsif phones.present?
          scope.where(phone_sql, phones: phones)
        else
          scope.where(email_sql, emails: emails)
        end
      else # "phone"
        return nil if phones.blank?
        scope.where(phone_sql, phones: phones)
      end
    end

    # Compara só os dígitos (ignora formatação) de phone e client_phone.
    def phone_sql
      "regexp_replace(coalesce(leads.phone, ''), '\\D', '', 'g') IN (:phones) OR " \
      "regexp_replace(coalesce(leads.client_phone, ''), '\\D', '', 'g') IN (:phones)"
    end

    def email_sql
      "lower(coalesce(leads.email, '')) IN (:emails) OR " \
      "lower(coalesce(leads.client_email, '')) IN (:emails)"
    end

    # Variações de telefone para tolerar prefixo 55 inconsistente.
    def phone_variants
      raw = [@lead.client_phone, @lead.phone].map { |phone| Phones::Normalizer.call(phone).to_s }.reject(&:blank?)
      variants = raw.flat_map do |digits|
        [digits, digits.delete_prefix("55")]
      end
      variants.reject(&:blank?).uniq
    end

    def email_variants
      [@lead.client_email, @lead.email].map { |e| e.to_s.strip.downcase }.reject(&:blank?).uniq
    end

    def eligible?(user)
      return false unless user&.active?

      if @setting.fallback_in_rule?
        candidate_ids.include?(user.id)
      else
        true
      end
    end

    def candidate_ids
      @candidate_ids ||= Array(@candidates).map(&:admin_user_id)
    end
  end
end
