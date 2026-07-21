# frozen_string_literal: true

module Habitations
  class ProprietorLinker
    def initialize(habitation)
      @habitation = habitation
    end

    def call
      if (proprietor = selected_proprietor)
        sync_habitation_from(proprietor)
        return proprietor
      end

      proprietor = existing_proprietor || new_proprietor
      return unless proprietor

      apply_habitation_data_to(proprietor)
      proprietor.save!
      sync_habitation_from(proprietor)
    rescue ActiveRecord::RecordInvalid
      nil
    end

    private

    attr_reader :habitation

    def selected_proprietor
      return if habitation.proprietor_id.blank?

      habitation.tenant.proprietors.find_by(id: habitation.proprietor_id)
    end

    def existing_proprietor
      find_by_vista_code ||
        find_by_cpf_cnpj ||
        find_by_phone ||
        find_by_email ||
        fallback_name_match
    end

    def new_proprietor
      return if owner_name.blank?

      habitation.tenant.proprietors.new(name: owner_name, role: :owner)
    end

    def find_by_vista_code
      legacy_vista_proprietor
    end

    def find_by_phone
      digits = Proprietor.normalized_phone(primary_phone)
      return if digits.blank?

      habitation.tenant.proprietors.with_normalized_phone(digits).order(:id).first
    end

    def find_by_cpf_cnpj
      digits = Proprietor.normalized_cpf_cnpj(owner_document)
      return if digits.blank?

      if Proprietor.cpf_digits_searchable?
        habitation.tenant.proprietors.where(cpf_cnpj_digits: digits).order(:id).first
      else
        habitation.tenant.proprietors
                  .where("regexp_replace(COALESCE(cpf_cnpj, ''), '\\D', '', 'g') = :digits", digits: digits)
                  .order(:id)
                  .first
      end
    end

    def find_by_email
      return if email.blank?

      habitation.tenant.proprietors.where("lower(trim(email)) = ?", email.downcase).order(:id).first
    end

    def find_by_name
      return if owner_name.blank?

      habitation.tenant.proprietors
                .where("lower(trim(name)) = ?", owner_name.to_s.strip.downcase)
                .order(:id)
                .first
    end

    def fallback_name_match
      return if owner_document.present? || primary_phone.present? || email.present?

      find_by_name
    end

    def legacy_vista_proprietor
      return if vista_code.blank?

      matches = habitation.tenant.proprietors.where(vista_code: vista_code).limit(2).to_a
      return unless matches.one?

      matches.first
    end

    def apply_habitation_data_to(proprietor)
      proprietor.name = owner_name if owner_name.present?
      proprietor.email = email if email.present?
      proprietor.mobile_phone = primary_phone if primary_phone.present?
      proprietor.business_phone ||= habitation.proprietario_telefone_comercial.presence
      proprietor.residential_phone ||= habitation.proprietario_telefone_residencial.presence
      proprietor.vista_code = vista_code if vista_code.present?
      proprietor.city = owner_city if owner_city.present?
    end

    def sync_habitation_from(proprietor)
      habitation.proprietor = proprietor
      habitation.proprietor_id = proprietor.id
      habitation.proprietario = proprietor.name
      habitation.proprietario_codigo = proprietor.vista_code
      habitation.proprietario_email = proprietor.email
      habitation.proprietario_celular = proprietor.mobile_phone.presence || proprietor.phone_primary
      habitation.proprietario_telefone_comercial = proprietor.business_phone
      habitation.proprietario_telefone_residencial = proprietor.residential_phone
      habitation.proprietario_cidade = proprietor.city
    end

    def owner_name
      @owner_name ||= habitation.proprietario.to_s.strip
    end

    def email
      @email ||= habitation.proprietario_email.to_s.strip
    end

    def primary_phone
      @primary_phone ||= habitation.proprietario_celular.to_s.strip
    end

    def vista_code
      @vista_code ||= habitation.proprietario_codigo.to_s.strip
    end

    def owner_document
      @owner_document ||= habitation.proprietario_codigo.to_s.strip
    end

    def owner_city
      @owner_city ||= habitation.proprietario_cidade.to_s.strip
    end
  end
end
