module Vista
  module TextEncodingNormalizer
    MOJIBAKE_PATTERN = /(?:Ã.|Â.|â[-œ]|�)/.freeze

    module_function

    def normalize(value)
      case value
      when String
        repair_mojibake(value)
      when Array
        value.map { |item| normalize(item) }
      when Hash
        value.transform_values { |item| normalize(item) }
      else
        value
      end
    end

    def repair_mojibake(text)
      return text unless text.match?(MOJIBAKE_PATTERN)

      repaired = text.encode(Encoding::Windows_1252).force_encoding(Encoding::UTF_8)
      return repaired if repaired.valid_encoding?

      fallback_repair(text)
    rescue EncodingError
      fallback_repair(text)
    end

    def fallback_repair(text)
      text
        .gsub("Ã¡", "á").gsub("Ã\u0081", "Á")
        .gsub("Ã ", "à").gsub("Ã€", "À")
        .gsub("Ã¢", "â").gsub("Ã‚", "Â")
        .gsub("Ã£", "ã").gsub("Ãƒ", "Ã")
        .gsub("Ã©", "é").gsub("Ã\u0089", "É")
        .gsub("Ãª", "ê").gsub("ÃŠ", "Ê")
        .gsub("Ã­", "í").gsub("Ã\u008d", "Í")
        .gsub("Ã³", "ó").gsub("Ã\u0093", "Ó")
        .gsub("Ã´", "ô").gsub("Ã”", "Ô")
        .gsub("Ãµ", "õ").gsub("Ã•", "Õ")
        .gsub("Ãº", "ú").gsub("Ã\u009a", "Ú")
        .gsub("Ã¼", "ü").gsub("Ãœ", "Ü")
        .gsub("Ã§", "ç").gsub("Ã‡", "Ç")
        .gsub("Âº", "º").gsub("Âª", "ª").gsub("Â²", "²")
        .gsub("â", "–").gsub("â", "—")
        .gsub("â", "“").gsub("â", "”")
        .gsub("â", "‘").gsub("â", "’")
        .gsub(/\bÃ(?=guas|gua|rea|ustria|pice|sis)/, "Á")
    end
  end
end
