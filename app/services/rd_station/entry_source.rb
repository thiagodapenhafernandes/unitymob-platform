module RdStation
  # Origem de aquisição, não o formulário nem a URL do perfil social do contato.
  class EntrySource
    OPTIONS = {
      "meta" => "Facebook / Instagram (Meta)", "google" => "Google",
      "tiktok" => "TikTok", "linkedin" => "LinkedIn", "email" => "E-mail",
      "organic" => "Busca orgânica", "referral" => "Sites de referência",
      "direct" => "Acesso direto", "unknown" => "Origem não identificada"
    }.freeze

    def self.normalize(value)
      I18n.transliterate(value.to_s).strip.downcase.gsub(/\s+/, " ")
    end

    def self.call(payload)
      contact = payload["contact"] || payload["lead"] || payload["data"] || payload
      contact = {} unless contact.is_a?(Hash)
      origin_value = contact["origin"] || contact.dig("funnel", "origin")
      origin = origin_value.is_a?(Hash) ? origin_value : {}
      source = [contact["utm_source"], origin["utm_source"], contact["traffic_source"], contact["source"], payload["utm_source"], origin_value]
        .find { |value| value.is_a?(String) && value.present? }
      medium = normalize(contact["utm_medium"] || origin["utm_medium"] || payload["utm_medium"])
      raw = normalize(source)
      key = case raw.split("|").last.to_s.strip
      when /\A(?:facebook|instagram|meta|fb|ig)(?:[ ._-].*)?\z/ then "meta"
      when /\Agoogle(?:[ ._-].*)?\z/ then "google"
      when /\Atiktok(?:[ ._-].*)?\z/ then "tiktok"
      when /\Alinkedin(?:[ ._-].*)?\z/ then "linkedin"
      when "email", "e-mail" then "email"
      when "organic", "organico", "busca organica" then "organic"
      when "referral", "referencia" then "referral"
      when "direct", "(direct)", "direto", "acesso direto" then "direct"
      when "", "unknown", "desconhecido", "(none)"
        tags = Array(contact["tags"] || contact["tag_list"]).flat_map { |tag| tag.to_s.split(",") }.map { |tag| normalize(tag) }
        if (tags & ["instagram leads", "facebook leads", "facebook lead ads", "meta ads"]).any?
          "meta"
        elsif %w[email organic referral].include?(medium)
          medium
        else
          "unknown"
        end
      else %w[email organic referral].include?(medium) ? medium : raw
      end
      { key: key, raw: raw }
    end
  end
end
