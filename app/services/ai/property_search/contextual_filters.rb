module Ai
  module PropertySearch
    class ContextualFilters
      NEW_SEARCH = /\b(nova busca|nova pesquisa|começar de novo|comecar de novo|do zero|agora (?:eu )?quero (?:uma|um|outro|outra))\b/i

      def initialize(setting:, text:, current_filters:, interpreted_filters:)
        @contract = FilterContract.new(setting)
        @text = text.to_s
        @current = @contract.normalize(current_filters)
        @interpreted = @contract.normalize(interpreted_filters)
      end

      def call
        filters = if @current.empty? || @text.match?(NEW_SEARCH)
          @interpreted
        else
          apply_explicit_removals(@current.merge(@interpreted))
        end

        Result.new(filters:, mode: @current.empty? || @text.match?(NEW_SEARCH) ? "new" : "refine")
      end

      Result = Data.define(:filters, :mode)

      private

      def apply_explicit_removals(filters)
        result = filters.deep_dup
        if @text.match?(/\b(?:tira|remova|remove|sem)\s+(?:o\s+|a\s+)?frente\s+(?:ao\s+)?mar\b/i)
          result["amenities"] = Array(result["amenities"]).reject { |item| I18n.transliterate(item).match?(/frente (?:ao )?mar/i) }
          result.delete("amenities") if result["amenities"].empty?
        end
        result.except!(*%w[price_min price_max]) if @text.match?(/\bsem (?:limite|faixa) de pre[cç]o\b/i)
        result.delete("neighborhood") if @text.match?(/\bsem (?:bairro|localiza[cç][aã]o)\b/i)
        result
      end

    end
  end
end
