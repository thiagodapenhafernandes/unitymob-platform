module Ai
  module PropertySearch
    # Traduz os filtros interpretados pela IA (vocabulário do contrato) para os parâmetros da listagem pública
    # (HabitationsController#search_params). Só repassa o que a listagem entende; o resto é descartado.
    class PublicParams
      TRANSACTIONS = { "sale" => "venda", "rent" => "aluguel" }.freeze
      COUNT_PARAMS = {
        "bedrooms_min" => "min_bedrooms", "suites_min" => "min_suites", "bathrooms_min" => "min_bathrooms",
        "parking_spaces_min" => "min_parking", "private_area_min" => "min_area", "private_area_max" => "max_area",
        "price_min" => "min_price", "price_max" => "max_price"
      }.freeze
      LABELS = {
        "property_type" => "Tipo", "city" => "Cidade", "neighborhood" => "Bairro", "development_name" => "Empreendimento",
        "bedrooms_min" => "Quartos", "suites_min" => "Suítes", "parking_spaces_min" => "Vagas", "price_min" => "Valor mínimo", "price_max" => "Valor máximo"
      }.freeze

      def self.summary(filters)
        filters = filters.to_h.stringify_keys
        LABELS.filter_map do |key, label|
          value = filters[key]
          next if value.blank?

          text = key.end_with?("_min") && key != "price_min" ? "#{value}+" : value
          text = ActionController::Base.helpers.number_to_currency(value, precision: 0, unit: "R$", format: "%u %n", delimiter: ".") if key.start_with?("price")
          "#{label}: #{text}"
        end
      end

      def initialize(filters, default_transaction: nil)
        @filters = filters.to_h.stringify_keys
        @default_transaction = default_transaction
      end

      def call
        params = {}
        transaction = TRANSACTIONS[@filters["transaction_type"]] || @default_transaction.presence_in(TRANSACTIONS.values)
        params["transaction_type"] = transaction if transaction
        params["category"] = [@filters["property_type"]] if @filters["property_type"].present?
        add_location(params)
        params["development"] = [@filters["development_name"]] if @filters["development_name"].present?
        COUNT_PARAMS.each { |key, name| params[name] = @filters[key].to_s.sub(/\.0\z/, "") if @filters[key].present? }
        params["search"] = @filters["property_code"] if @filters["property_code"].present?
        params["characteristics"] = ["lancamento_flag"] if @filters["property_condition"] == "launch"
        params
      end

      private

      # A listagem usa "Bairro - Cidade" no mesmo campo das cidades (igual ao formulário de busca do site).
      def add_location(params)
        city = @filters["city"].presence
        neighborhood = @filters["neighborhood"].presence
        if neighborhood && city
          params["city"] = ["#{neighborhood} - #{city}"]
        elsif neighborhood
          params["neighborhood"] = neighborhood
        elsif city
          params["city"] = [city]
        end
      end
    end
  end
end
