# frozen_string_literal: true

module Proprietors
  class DuplicateAnalyzer
    REFERENCING_TABLES = %w[
      habitations
      habitation_interactions
      client_interactions
      crm_appointments
      client_property_interests
    ].freeze

    COMPANY_TERMS = /\b(empreendimentos|negocios|negócios|imobiliarios|imobiliários|construtora|incorporadora|imoveis|imóveis)\b/i

    Candidate = Struct.new(
      :tenant_id,
      :match_type,
      :match_key,
      :risk,
      :reason,
      :canonical_id,
      :duplicate_ids,
      :proprietor_count,
      :linked_records_count,
      :canonical_snapshot,
      :duplicate_snapshots,
      keyword_init: true
    )

    def initialize(tenant_scope: Tenant.all)
      @tenant_scope = tenant_scope
    end

    def call
      tenant_scope.flat_map { |tenant| candidates_for(tenant) }
    end

    def summary
      candidates = call
      {
        tenants: tenant_scope.count,
        candidates: candidates.size,
        automatic_candidates: candidates.count { |candidate| candidate.risk == "automatic_candidate" },
        review_required: candidates.count { |candidate| candidate.risk == "review_required" },
        high_risk: candidates.count { |candidate| candidate.risk == "high_risk" }
      }
    end

    private

    attr_reader :tenant_scope

    def candidates_for(tenant)
      groups_for(tenant).filter_map do |match_type, match_key, proprietors|
        next if proprietors.size < 2

        build_candidate(tenant, match_type, match_key, proprietors)
      end
    end

    def groups_for(tenant)
      indexed = {}

      tenant.proprietors.find_each do |proprietor|
        normalized_name_value = normalized_name(proprietor.name)
        normalized_phones_value = normalized_phones(proprietor)

        add_group(indexed, "cpf_cnpj", proprietor.cpf_cnpj_digits, proprietor)
        add_group(indexed, "email", normalized_email(proprietor.email), proprietor)
        normalized_phones_value.each { |phone| add_group(indexed, "phone", phone, proprietor) }
        if normalized_name_value.present?
          normalized_phones_value.each { |phone| add_group(indexed, "exact_name_phone", "#{normalized_name_value}|#{phone}", proprietor) }
        end
        add_group(indexed, "name", normalized_name_value, proprietor)
        add_group(indexed, "name_family", company_family_name(proprietor.name), proprietor)
      end

      indexed.map { |key, proprietors| [key.first, key.second, proprietors.uniq] }
    end

    def add_group(indexed, type, key, proprietor)
      key = key.to_s.strip
      return if key.blank?

      indexed[[type, key]] ||= []
      indexed[[type, key]] << proprietor
    end

    def build_candidate(tenant, match_type, match_key, proprietors)
      canonical = proprietors.max_by { |proprietor| canonical_score(tenant, proprietor) }
      duplicates = proprietors - [canonical]
      risk, reason = classify(match_type, match_key, proprietors, canonical, duplicates)

      Candidate.new(
        tenant_id: tenant.id,
        match_type: match_type,
        match_key: match_key,
        risk: risk,
        reason: reason,
        canonical_id: canonical.id,
        duplicate_ids: duplicates.map(&:id),
        proprietor_count: proprietors.size,
        linked_records_count: proprietors.sum { |proprietor| linked_records_count(proprietor) },
        canonical_snapshot: snapshot(canonical),
        duplicate_snapshots: duplicates.map { |proprietor| snapshot(proprietor) }
      )
    end

    def canonical_score(tenant, proprietor)
      [
        linked_records_count(proprietor),
        field_presence_score(proprietor),
        proprietor.vista_code.present? ? 1 : 0,
        proprietor.created_at ? -proprietor.created_at.to_i : 0,
        -proprietor.id
      ]
    end

    def field_presence_score(proprietor)
      %i[
        name vista_code cpf_cnpj_digits email phone_primary mobile_phone residential_phone
        business_phone city street cep notes
      ].count { |field| proprietor.public_send(field).present? }
    end

    def linked_records_count(proprietor)
      REFERENCING_TABLES.sum do |table|
        ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql_array(["SELECT COUNT(*) FROM #{table} WHERE proprietor_id = ?", proprietor.id])
        ).to_i
      end
    end

    def classify(match_type, match_key, proprietors, canonical = nil, duplicates = nil)
      return ["automatic_candidate", "Mesmo CPF/CNPJ ou e-mail"] if %w[cpf_cnpj email].include?(match_type)

      if match_type == "exact_name_phone"
        if safe_exact_name_phone_merge?(proprietors, canonical, duplicates)
          return ["automatic_candidate", "Mesmo nome e telefone, sem conflitos e sem vínculos nos duplicados"]
        end

        return ["review_required", "Mesmo nome e telefone, mas exige revisão por vínculo ou conflito cadastral"]
      end

      if match_type == "phone"
        if proprietors.size > 5
          return ["high_risk", "Telefone aparece em muitos cadastros; pode ser telefone corporativo ou genérico"]
        end

        return ["review_required", "Mesmo telefone; revisar se é pessoa/empresa única antes de fundir"]
      end

      if match_type == "name_family"
        if proprietors.size > 10
          return ["high_risk", "Família de nome com muitos cadastros; exige revisão manual em lote"]
        end

        return ["review_required", "Variações do mesmo radical de nome; revisar antes de fundir"]
      end

      if high_risk_name?(match_key, proprietors)
        ["high_risk", "Nome curto/generico ou grupo grande; exige revisão manual"]
      else
        ["review_required", "Mesmo nome normalizado; revisar documento, telefone, e-mail e imóveis antes de fundir"]
      end
    end

    def high_risk_name?(match_key, proprietors)
      match_key.length <= 3 ||
        proprietors.size > 10 ||
        (match_key.exclude?(" ") && match_key !~ COMPANY_TERMS)
    end

    def safe_exact_name_phone_merge?(proprietors, canonical, duplicates)
      return false if canonical.blank? || duplicates.blank?
      return false if proprietors.any? { |proprietor| linked_records_count(proprietor).positive? && proprietor != canonical }

      non_conflicting_values?(proprietors.map(&:cpf_cnpj_digits)) &&
        non_conflicting_values?(proprietors.map { |proprietor| normalized_email(proprietor.email) })
    end

    def non_conflicting_values?(values)
      values.compact_blank.uniq.size <= 1
    end

    def snapshot(proprietor)
      {
        id: proprietor.id,
        name: proprietor.name,
        role: proprietor.role,
        vista_code: proprietor.vista_code,
        email: proprietor.email,
        phone_primary: proprietor.phone_primary,
        mobile_phone: proprietor.mobile_phone,
        city: proprietor.city,
        linked_records_count: linked_records_count(proprietor)
      }
    end

    def normalized_name(value)
      I18n.transliterate(value.to_s).downcase.squish
    end

    def company_family_name(value)
      full_name = normalized_name(value)
      return if full_name.blank?
      return unless full_name.match?(/\d/) || full_name.match?(COMPANY_TERMS)

      root = full_name
             .gsub(COMPANY_TERMS, " ")
             .gsub(/\b(ltda|me|s\/a|sa|e|de|da|do|das|dos)\b/i, " ")
             .squish

      root = root.split.first if root.split.size > 1 && root.match?(/\d/)
      return if root.blank? || root.length < 2

      root
    end

    def normalized_email(value)
      value.to_s.downcase.strip
    end

    def normalized_phones(proprietor)
      [
        proprietor.phone_primary,
        proprietor.mobile_phone,
        proprietor.residential_phone,
        proprietor.business_phone
      ].filter_map do |phone|
        digits = Proprietor.normalized_phone(phone)
        digits if digits.length >= 8
      end.uniq
    end
  end
end
