module Phones
  class PublicWhatsapp
    INVALID = "Informe um WhatsApp válido com DDD, por exemplo (47) 99123-4567.".freeze
    FIXED = "Esse número parece ser de telefone fixo. Informe um número de WhatsApp (celular).".freeze
    INTERNATIONAL = "Para número de outro país, comece com + e o código do país, por exemplo +351 912 345 678.".freeze

    attr_reader :e164, :error

    def initialize(value)
      raw = value.to_s.strip
      digits = raw.gsub(/\D/, "")
      @error = INVALID
      return unless raw.match?(/\A\+?[\d\s().-]+\z/)
      if !raw.start_with?("+") && digits.length > 11
        @error = INTERNATIONAL
        return
      end

      number = Phonelib.parse(raw.start_with?("+") ? "+#{digits}" : "+55#{digits}")
      return unless number.valid? && number.extension.blank?
      if number.country == "BR"
        unless number.type == :mobile
          @error = FIXED
          return
        end
        return unless number.national(false).gsub(/\D/, "").match?(/\A\d{2}9\d{8}\z/)
        return if digits.match?(/(\d)\1{7}\z/)
      end

      @e164 = number.full_e164
      @error = nil
    end
  end
end
