module Habitation::PriceFormatting
  extend ActiveSupport::Concern

  included do
    %w[valor_venda valor_locacao valor_locacao_anterior valor_condominio valor_iptu valor_promocional valor_por_m2 valor_venda_anterior valor_aceito_permuta permuta_valor permuta_veiculo_valor permuta_outros_valor saldo_devedor valor_comissao valor_livre_proprietario valor_alugado_terceiros valor_vendido_terceiros].each do |field|
      # Defines setter: "R$ 1.234,56" -> 123456 (cents)
      define_method("#{field}_formatted=") do |value|
        if value.blank?
          public_send("#{field}_cents=", nil)
          next
        end

        # Remove everything that is not a digit or a comma
        clean_value = value.to_s.gsub(/[^\d,]/, '')
        
        # Replace comma with dot to convert to float
        numeric_value = clean_value.tr(',', '.')
        
        # Convert to cents (integer)
        cents_value = (numeric_value.to_f * 100).round

        public_send("#{field}_cents=", cents_value)
      end

      # Defines getter: 123456 -> "R$ 1.234,56"
      define_method("#{field}_formatted") do
        cents = public_send("#{field}_cents")
        return nil if cents.blank?

        ActiveSupport::NumberHelper.number_to_currency(
          cents / 100.0,
          separator: ",",
          delimiter: ".",
          precision: 2
        )
      end
    end
  end
end
