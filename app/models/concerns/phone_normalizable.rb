# frozen_string_literal: true

module PhoneNormalizable
  extend ActiveSupport::Concern

  class_methods do
    def normalize_phone_fields(*field_names, default_country: "BR")
      @phone_fields_to_normalize ||= {}
      field_names.flatten.each do |field_name|
        @phone_fields_to_normalize[field_name.to_sym] = default_country
      end

      before_validation :normalize_configured_phone_fields
    end

    def phone_fields_to_normalize
      @phone_fields_to_normalize || {}
    end
  end

  private

  def normalize_configured_phone_fields
    self.class.phone_fields_to_normalize.each do |field_name, default_country|
      next unless has_attribute?(field_name)

      raw_value = public_send(field_name)
      normalized = Phones::Normalizer.call(raw_value, default_country:)
      public_send("#{field_name}=", normalized)
    end
  end
end
