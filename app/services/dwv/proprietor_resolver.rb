# frozen_string_literal: true

module Dwv
  class ProprietorResolver
    Result = Struct.new(:proprietor, :action, :matched_by, keyword_init: true)

    def initialize(tenant:, name:, email: nil, phone_primary: nil, mobile_phone: nil, business_phone: nil, cpf_cnpj: nil, persist: true)
      @tenant = tenant
      @name = name.to_s.squish
      @email = email.to_s.strip.presence
      @phone_primary = phone_primary.to_s.strip.presence
      @mobile_phone = mobile_phone.to_s.strip.presence
      @business_phone = business_phone.to_s.strip.presence
      @cpf_cnpj = cpf_cnpj.to_s.strip.presence
      @persist = persist
    end

    def call
      return Result.new(action: :ignored) if tenant.blank? || name.blank?

      if (proprietor = best_exact_name_match)
        update_existing(proprietor)
        return Result.new(proprietor: proprietor, action: :matched, matched_by: :name)
      end

      if (proprietor = document_match)
        update_existing(proprietor)
        return Result.new(proprietor: proprietor, action: :matched, matched_by: :cpf_cnpj)
      end

      if (proprietor = email_match)
        update_existing(proprietor)
        return Result.new(proprietor: proprietor, action: :matched, matched_by: :email)
      end

      return Result.new(action: :would_create) unless persist

      proprietor = tenant.proprietors.create!(creation_attributes)
      Result.new(proprietor: proprietor, action: :created)
    end

    private

    attr_reader :tenant, :name, :email, :phone_primary, :mobile_phone, :business_phone, :cpf_cnpj, :persist

    def best_exact_name_match
      matches = tenant.proprietors.where("LOWER(TRIM(name)) = ?", name.downcase).to_a
      matches.max_by { |proprietor| proprietor_score(proprietor) }
    end

    def document_match
      digits = Proprietor.normalized_cpf_cnpj(cpf_cnpj)
      return if digits.blank?

      scope =
        if Proprietor.cpf_digits_searchable?
          tenant.proprietors.where(cpf_cnpj_digits: digits)
        else
          tenant.proprietors.where("regexp_replace(COALESCE(cpf_cnpj, ''), '\\D', '', 'g') = :digits", digits: digits)
        end

      scope.order(:id).first
    end

    def email_match
      return if email.blank?

      tenant.proprietors.where("LOWER(TRIM(email)) = ?", email.downcase).order(:id).first
    end

    def update_existing(proprietor)
      return unless persist

      missing_contact_attributes.each do |attribute, value|
        proprietor.public_send("#{attribute}=", value) if proprietor.public_send(attribute).blank? && value.present?
      end
      proprietor.save! if proprietor.changed?
    end

    def creation_attributes
      {
        name: name,
        role: "builder"
      }.merge(missing_contact_attributes).compact_blank
    end

    def missing_contact_attributes
      {
        email: email,
        phone_primary: phone_primary,
        mobile_phone: mobile_phone,
        business_phone: business_phone,
        cpf_cnpj: cpf_cnpj
      }
    end

    def proprietor_score(proprietor)
      [
        linked_records_count(proprietor),
        field_presence_score(proprietor),
        proprietor.vista_code.present? ? 1 : 0,
        proprietor.created_at ? -proprietor.created_at.to_i : 0,
        -proprietor.id
      ]
    end

    def linked_records_count(proprietor)
      Proprietors::DuplicateAnalyzer::REFERENCING_TABLES.sum do |table|
        ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql_array(["SELECT COUNT(*) FROM #{table} WHERE proprietor_id = ?", proprietor.id])
        ).to_i
      end
    end

    def field_presence_score(proprietor)
      %i[
        name vista_code cpf_cnpj_digits email phone_primary mobile_phone residential_phone
        business_phone city street cep notes
      ].count { |field| proprietor.respond_to?(field) && proprietor.public_send(field).present? }
    end
  end
end
