module Api
  module V1
    class PropertyFeaturesController < PropertyIntakeIntegrationController
      def index
        options = @intake_tenant.attribute_options.for_context("habitation")
          .where(category: %w[feature infrastructure]).order(name: :asc).group_by(&:category)
        if params.key?(:categoria)
          category = Habitation.registration_category(params[:categoria])
          return render json: { error: "categoria inválida" }, status: :unprocessable_entity unless category

          property = @intake_tenant.habitations.new(categoria: category)
        end
        render json: {
          caracteristicas_internas: serialize_options(options["feature"], property, "feature"),
          infraestrutura_lazer: serialize_options(options["infrastructure"], property, "infrastructure")
        }
      end

      private

      def serialize_options(records, property, kind)
        records = Array(records)
        return records.map { |option| { id: option.id, nome: option.name } } unless property

        by_name = records.index_by { |option| AttributeOption.normalized_name_key(option.name) }
        property.available_checklist_options(kind, catalog: records.map(&:name)).map do |name|
          option = by_name[AttributeOption.normalized_name_key(name)]
          { id: option&.id, nome: option&.name || name }
        end
      end
    end
  end
end
