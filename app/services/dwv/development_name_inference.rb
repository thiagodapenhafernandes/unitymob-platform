module Dwv
  # Reconhece, a partir de textos livres do payload DWV (complemento do endereço,
  # unit_info, etc.), quando o valor é o nome de um empreendimento/condomínio/
  # residencial — e não um localizador de unidade ("Casa 2", "Apto 101", "Fundos")
  # ou um descritor genérico ("Condomínio Fechado").
  #
  # A DWV frequentemente entrega, em imóveis de terceiros, o nome do condomínio no
  # complemento do endereço em vez de num campo de empreendimento. Sem esta
  # inferência, o nome só aparece grudado no endereço e nunca no título do card.
  module DevelopmentNameInference
    module_function

    # Marcadores fortes: a presença já caracteriza nome de empreendimento
    # (comparação feita sobre o texto sem acento e em minúsculas).
    STRONG_MARKERS = /\b(residencial|residencias?|residencia|residence|village|villaggio|resort|loteamento|aldeia|mansao|mansoes)\b/.freeze

    # Marcadores medianos: caracterizam nome de empreendimento quando acompanhados
    # de um nome próprio (garantido pela exigência de 2+ palavras). Inclui as
    # abreviações brasileiras usuais (ED., EDIF., COND., RESID., TORRE).
    MEDIUM_MARKERS = /\b(condominio|cond|edificio|edif|edf|ed|resid|park|garden|gardens|portal|solar|morada|jardim|jardins|clube|reserva|parque|villa|villas|home|homes|tower|towers|torre|torres|ville)\b/.freeze

    # Localizadores de unidade — nunca são nome de empreendimento.
    UNIT_LOCATOR = /\A(casa|sobrado|apto|apartamento|ap|bloco|bl|lote|lt|quadra|qd|sala|loja|galpao|box|vaga|unidade|un|und|fundos|frente|terreo|pavimento|pav|andar|cobertura|cob)\b[\s\-]*[a-z0-9]{0,4}\z/.freeze

    # Descritores genéricos de condomínio/tipo — contêm um marcador, mas não são
    # nome próprio de empreendimento.
    GENERIC_DESCRIPTORS = [
      "condominio", "condominio fechado", "condominio aberto", "condominio de casas",
      "condominio horizontal", "condominio vertical", "condominio residencial",
      "casa", "casa em condominio", "residencial", "residence", "residencia",
      "village", "resort", "loteamento"
    ].freeze

    # Retorna o primeiro texto que se caracteriza como nome de empreendimento,
    # preservando a grafia original (com acentos/caixa). Aceita vários candidatos.
    def call(*texts)
      texts.flatten.each do |raw|
        cleaned = clean(raw)
        return cleaned if cleaned.present? && development_name?(cleaned)
      end
      nil
    end

    def development_name?(text)
      cleaned = clean(text)
      return false if cleaned.blank? || cleaned.length < 5
      # Nome de empreendimento "limpo" não tem dígito; a presença de número indica
      # localizador de unidade misturado (ex.: "Apartamento 403 - Torre 1", "Residência 6").
      return false if cleaned.match?(/\d/)

      folded = fold(cleaned)
      return false if GENERIC_DESCRIPTORS.include?(folded)
      return false if UNIT_LOCATOR.match?(folded)
      return false if folded.split(/\s+/).size < 2

      folded.match?(STRONG_MARKERS) || folded.match?(MEDIUM_MARKERS)
    end

    def clean(text)
      text.to_s.squish.presence
    end

    def fold(text)
      I18n.transliterate(text.to_s).downcase.strip
    end
  end
end
