module InterestIntelligence
  module BusinessType
    def self.normalize(value)
      case value.to_s.parameterize
      when "venda", "sale", "compra", "comprar" then "venda"
      when "locacao", "aluguel", "rental", "rent", "alugar" then "locacao"
      end
    end

    def self.price_for(habitation, business_type = nil)
      return habitation.valor_venda_cents if business_type == "venda"
      return habitation.valor_locacao_cents if business_type == "locacao"

      habitation.valor_venda_cents.to_i.positive? ? habitation.valor_venda_cents : habitation.valor_locacao_cents
    end

    def self.for_property(habitation)
      sale = habitation.valor_venda_cents.to_i.positive?
      rental = habitation.valor_locacao_cents.to_i.positive?
      return "venda" if sale && !rental
      return "locacao" if rental && !sale
    end
  end
end
