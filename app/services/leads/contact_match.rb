module Leads
  # Match de contato reutilizado pela fidelização e pelo complemento de
  # consultas: encontra leads anteriores da mesma pessoa (telefone/e-mail),
  # tolerando formatação e prefixo 55 inconsistente.
  module ContactMatch
    def self.apply(scope, lead, match_mode)
      phones = phone_variants_for(lead)
      emails = email_variants_for(lead)

      case match_mode.to_s
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

    def self.phone_variants_for(lead)
      raw = [lead.client_phone, lead.phone].map { |phone| Phones::Normalizer.call(phone).to_s }.reject(&:blank?)
      raw.flat_map { |digits| [digits, digits.delete_prefix("55")] }.reject(&:blank?).uniq
    end

    def self.email_variants_for(lead)
      [lead.client_email, lead.email].map { |email| email.to_s.strip.downcase }.reject(&:blank?).uniq
    end

    # Compara só os dígitos (ignora formatação) de phone e client_phone.
    def self.phone_sql
      "regexp_replace(coalesce(leads.phone, ''), '\\D', '', 'g') IN (:phones) OR " \
        "regexp_replace(coalesce(leads.client_phone, ''), '\\D', '', 'g') IN (:phones)"
    end

    def self.email_sql
      "lower(coalesce(leads.email, '')) IN (:emails) OR " \
        "lower(coalesce(leads.client_email, '')) IN (:emails)"
    end
  end
end
