module Habitations
  class ExternalIntakeSearch
    def initialize(tenant, filters)
      @tenant = tenant
      @filters = filters
    end

    def call
      @filters.each do |key, value|
        raise ExternalIntake::Invalid, "#{key} inválido" unless value.is_a?(String) && value.bytesize <= 255 && !value.include?("\0")
      end
      unless @filters["numero"].present? && (@filters["cep"].present? ||
          (@filters["logradouro"].present? && @filters["cidade"].present? && @filters["uf"].present?))
        raise ExternalIntake::Invalid, "Informe número e CEP ou número, logradouro, cidade e UF"
      end

      scope = @tenant.habitations.joins(:address).includes(:address)
      @filters.each do |key, value|
        next if value.blank? && key != "complemento"

        column = key == "torre" ? "habitations.bloco" : "addresses.#{key}"
        if key == "cep"
          raise ExternalIntake::Invalid, "cep inválido" unless value.match?(/\A\d{5}-?\d{3}\z/)

          scope = scope.where("REPLACE(#{column}, '-', '') = ?", value.delete("-"))
        else
          scope = scope.where("LOWER(unaccent(TRIM(COALESCE(#{column}, '')))) = LOWER(unaccent(?))", value.strip)
        end
      end
      scope.order(:id).limit(50).map do |property|
        {
          codigo: property.codigo,
          endereco: property.address.attributes.slice("logradouro", "numero", "complemento", "bairro", "cidade", "uf", "cep"),
          torre: property.bloco, categoria: property.categoria, modalidade: property.modalidade,
          status: property.intake_submitted_for_admin_review? ? "em_revisao" : (property.inactive_commercial_status? ? "inativo" : "ativo")
        }
      end
    end
  end
end
