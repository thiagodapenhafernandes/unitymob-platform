module Ai
  module PropertySearch
    class ResultPresenter
      def initialize(setting)
        @fields = setting.ai_property_search_result_fields
      end

      def call(habitation)
        values = {
          "id" => habitation.id,
          "path" => Rails.application.routes.url_helpers.admin_habitation_path(habitation),
          "cover_image" => cover_image(habitation),
          "property_code" => habitation.codigo,
          "title" => habitation.display_title,
          "neighborhood" => habitation.address&.bairro.presence || habitation.bairro,
          "city" => habitation.address&.cidade.presence || habitation.cidade,
          "price" => price(habitation),
          "bedrooms" => habitation.dormitorios_qtd,
          "suites" => habitation.suites_qtd,
          "parking_spaces" => habitation.vagas_qtd,
          "private_area" => habitation.area_privativa_m2,
          "development_name" => habitation.nome_empreendimento
        }
        values.slice("id", "path", *@fields).compact
      end

      private

      def cover_image(habitation)
        source = habitation.public_image_sources.first
        Storage::PublicCdnImageUrl.resolve(source, resize_to_fill: [640, 480], format: :webp) if source
      rescue StandardError
        nil
      end

      def price(habitation)
        cents = habitation.valor_venda_cents.to_i.positive? ? habitation.valor_venda_cents : habitation.valor_locacao_cents
        cents.positive? ? cents / 100.0 : nil
      end
    end
  end
end
