# frozen_string_literal: true

module Phones
  class Normalizer
    BRAZIL_COUNTRY_CODE = "55"
    MIN_E164_LENGTH = 8
    MAX_E164_LENGTH = 15

    class << self
      def call(value, default_country: "BR")
        new(value, default_country:).call
      end

      def display(value)
        digits = call(value)
        return "" if digits.blank?

        return format_brazilian(digits) if digits.start_with?(BRAZIL_COUNTRY_CODE)

        "+#{digits}"
      end

      def valid?(value, default_country: "BR")
        call(value, default_country:).present?
      end

      private

      def format_brazilian(digits)
        national = digits.delete_prefix(BRAZIL_COUNTRY_CODE)
        return "+#{digits}" unless national.length.in?([10, 11])

        ddd = national.first(2)
        number = national.from(2)
        if number.length == 9
          "+55 (#{ddd}) #{number.first(5)}-#{number.last(4)}"
        else
          "+55 (#{ddd}) #{number.first(4)}-#{number.last(4)}"
        end
      end
    end

    def initialize(value, default_country: "BR")
      @value = value
      @default_country = default_country.to_s.upcase.presence || "BR"
    end

    def call
      digits = raw_digits
      return if digits.blank?
      return if placeholder?(digits)

      normalized = normalize_digits(digits)
      return unless e164_digits?(normalized)

      normalized
    end

    private

    attr_reader :value, :default_country

    def raw_digits
      value.to_s.gsub(/\D/, "")
    end

    def normalize_digits(digits)
      digits = digits.sub(/\A00+/, "")

      return digits if value.to_s.strip.start_with?("+")
      return digits if digits.start_with?(BRAZIL_COUNTRY_CODE) && digits.length.in?([12, 13])
      return "#{BRAZIL_COUNTRY_CODE}#{digits}" if default_country == "BR" && digits.length.in?([10, 11])

      digits
    end

    def e164_digits?(digits)
      digits.length.between?(MIN_E164_LENGTH, MAX_E164_LENGTH)
    end

    def placeholder?(digits)
      digits.chars.uniq == ["0"]
    end
  end
end
