module Leads
  # Cartão de contato (vCard 3.0) do lead para o corretor salvar na agenda do
  # celular com nome padronizado — "[Unitymob] Nome". Servido pelo botão na
  # ficha do lead (com login) e pelo link seguro da notificação WhatsApp.
  class Vcard
    NAME_PREFIX = "[Unitymob]".freeze

    def self.content(lead)
      new(lead).content
    end

    def self.card(lead)
      new(lead).card
    end

    def self.filename(lead)
      safe_name = I18n.transliterate("#{NAME_PREFIX} #{lead.display_name}".strip).gsub(/[^\w\-+. \[\]]/, "").squish
      "#{safe_name}.vcf"
    end

    def initialize(lead)
      @lead = lead
    end

    def content
      lines = ["BEGIN:VCARD", "VERSION:3.0", "FN:#{escape(full_name)}", "N:#{structured_name}"]
      lines << "TEL;TYPE=CELL,VOICE:#{phone}" if phone.present?
      lines << "EMAIL:#{escape(email)}" if email.present?
      lines << "ORG:#{escape(@lead.tenant&.name.to_s)}" if @lead.tenant&.name.present?
      lines << "END:VCARD"
      lines.join("\r\n") + "\r\n"
    end

    # Cartão de contato nativo da Cloud API (botão "Salvar contato" no aviso).
    def card
      parts = @lead.display_name.to_s.split
      {
        name: {
          formatted_name: full_name,
          first_name: parts.first.to_s,
          last_name: parts.size > 1 ? parts.last.to_s : ""
        },
        phones: phone.present? ? [{ phone: phone, type: "CELL" }] : [],
        emails: email.present? ? [{ email: email, type: "WORK" }] : [],
        org: { company: @lead.tenant&.name.to_s }
      }.compact_blank
    end

    private

    def full_name
      "#{NAME_PREFIX} #{@lead.display_name}".strip
    end

    def structured_name
      parts = @lead.display_name.to_s.split
      last = parts.size > 1 ? parts.last : ""
      first = parts.size > 1 ? parts[0..-2].join(" ") : parts.first.to_s
      "#{escape(last)};#{escape(first)};;;"
    end

    def phone
      digits = Phones::Normalizer.call(@lead.display_phone).to_s
      digits.present? ? "+#{digits}" : nil
    end

    def email
      @lead.display_email.to_s.strip.presence
    end

    # Escapes do vCard 3.0 (RFC 2426 §5.8.1).
    def escape(value)
      value.to_s.gsub("\\", "\\\\").gsub(";", "\\;").gsub(",", "\\,").gsub(/\r?\n/, "\\n")
    end
  end
end
