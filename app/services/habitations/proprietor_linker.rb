# frozen_string_literal: true

module Habitations
  class ProprietorLinker
    def initialize(habitation)
      @habitation = habitation
    end

    def call
      proprietor = selected_proprietor || existing_proprietor || new_proprietor
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

      Proprietor.find_by(id: habitation.proprietor_id)
    end

    def existing_proprietor
      find_by_vista_code ||
        Proprietor.find_by_phone(primary_phone) ||
        find_by_email ||
        find_by_name
    end

    def new_proprietor
      return if owner_name.blank?

      Proprietor.new(name: owner_name, role: :owner)
    end

    def find_by_vista_code
      return if vista_code.blank?

      Proprietor.find_by(vista_code: vista_code)
    end

    def find_by_email
      return if email.blank?

      Proprietor.find_by(email: email)
    end

    def find_by_name
      return if owner_name.blank?

      Proprietor.find_by(name: owner_name)
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
      habitation.proprietor_id = proprietor.id
      habitation.proprietario = proprietor.name if proprietor.name.present?
      habitation.proprietario_codigo = proprietor.vista_code if proprietor.vista_code.present?
      habitation.proprietario_email = proprietor.email if proprietor.email.present?
      if proprietor.mobile_phone.present? || proprietor.phone_primary.present?
        habitation.proprietario_celular = proprietor.mobile_phone.presence || proprietor.phone_primary
      end
      habitation.proprietario_telefone_comercial = proprietor.business_phone if proprietor.business_phone.present?
      habitation.proprietario_telefone_residencial = proprietor.residential_phone if proprietor.residential_phone.present?
      habitation.proprietario_cidade = proprietor.city if proprietor.city.present?
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

    def owner_city
      @owner_city ||= habitation.proprietario_cidade.to_s.strip
    end
  end
end
