# frozen_string_literal: true

module Habitations
  # Compõe o título do anúncio no padrão do prompt da IA (Salute v2):
  #   [TIPO] [VENDA|ALUGUEL ANUAL] [DORMITÓRIOS] prep [BAIRRO] | [EMPREENDIMENTO]
  #
  # Regras linguísticas sem hardcode de nomes próprios:
  # - preposição: mapa mínimo de contrações (só bairros certos/irregulares);
  #   desconhecido cai em "em {bairro}", sempre gramatical;
  # - transação: deriva de sale_listing?/rental_listing? (status + valores);
  # - dormitórios: regra das suítes do prompt;
  # - nome de empreendimento genérico (vazio, igual à categoria, curto)
  #   invalida a composição em vez de gerar lixo.
  class TitleComposer
    Result = Struct.new(:title, :skip_reason, :tier, keyword_init: true)

    MAX_CHARS = 80

    # Fonte: mapa do usuário (5) + extensões morfologicamente seguras.
    # Bairros fora daqui usam "em" (correto, só menos idiomático).
    NEIGHBORHOOD_PREPOSITIONS = {
      "Centro" => "no",
      "Barra Sul" => "na",
      "Praia Brava" => "na",
      "Pioneiros" => "no",
      "Estados" => "nos",
      "Barra Norte" => "na",
      "Barra" => "na",
      "Meia Praia" => "na",
      "Praia dos Amores" => "na",
      "Praia do Estaleiro" => "na",
      "Fazenda" => "na",
      "Fazendinha" => "na",
      "Nações" => "nas",
      "Jardim Dourado" => "no",
      "Tabuleiro" => "no",
      "Estaleiro" => "no",
      "Estaleirinho" => "no",
      "São Francisco de Assis" => "no",
      "Sertão Santa Luzia" => "no",
      "Condomínio Caledônia" => "no"
    }.freeze

    DEFAULT_PREPOSITION = "em"

    def self.compose(habitation)
      new(habitation).compose
    end

    def initialize(habitation)
      @habitation = habitation
    end

    def compose
      categoria = @habitation.categoria.to_s.squish
      return skipped(:blank_categoria) if categoria.blank?

      transaction = transaction_text
      return skipped(:unknown_transaction) if transaction.nil?

      empreendimento = clean_empreendimento(categoria)
      return skipped(:invalid_empreendimento) if empreendimento.nil?

      bedrooms = bedrooms_text
      location = location_text

      full = [categoria, transaction, bedrooms, location, "| #{empreendimento}"].compact.join(" ").squish
      return Result.new(title: full, tier: :full) if full.length <= MAX_CHARS

      without_bedrooms = [categoria, transaction, location, "| #{empreendimento}"].compact.join(" ").squish
      return Result.new(title: without_bedrooms, tier: :no_bedrooms) if without_bedrooms.length <= MAX_CHARS

      without_location = [categoria, transaction, bedrooms, "| #{empreendimento}"].compact.join(" ").squish
      return Result.new(title: without_location, tier: :no_location) if without_location.length <= MAX_CHARS

      Result.new(title: full, tier: :over_limit)
    end

    private

    def skipped(reason)
      Result.new(title: nil, skip_reason: reason)
    end

    def transaction_text
      return "à venda" if @habitation.sale_listing?
      return "Aluguel Anual" if @habitation.rental_listing?

      nil
    end

    def clean_empreendimento(categoria)
      nome = @habitation.nome_empreendimento.to_s.squish
      return nil if nome.length < 3
      return nil if nome.casecmp?(categoria)

      nome
    end

    def bedrooms_text
      dorms = @habitation.dormitorios_qtd.to_i
      suites = @habitation.suites_qtd.to_i
      return nil if dorms.zero? && suites.zero?
      return "#{suites} #{suites == 1 ? 'suíte' : 'suítes'}" if dorms.zero? || dorms == suites
      return "#{dorms} #{dorms == 1 ? 'dormitório' : 'dormitórios'}" if suites.zero?

      "#{dorms} dormitórios, #{suites} #{suites == 1 ? 'suíte' : 'suítes'}"
    end

    def location_text
      bairro = @habitation.bairro.to_s.squish
      return nil if bairro.blank?

      "#{NEIGHBORHOOD_PREPOSITIONS.fetch(bairro, DEFAULT_PREPOSITION)} #{bairro}"
    end
  end
end
