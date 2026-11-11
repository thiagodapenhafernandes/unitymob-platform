module Api
  module V1
    class PropertyFeaturesController < PropertyIntakeIntegrationController
      def index
        options = @intake_tenant.attribute_options.for_context("habitation")
          .where(category: %w[feature infrastructure]).order(name: :asc).group_by(&:category)
        render json: {
          caracteristicas_internas: Array(options["feature"]).map { |option| { id: option.id, nome: option.name } },
          infraestrutura_lazer: Array(options["infrastructure"]).map { |option| { id: option.id, nome: option.name } }
        }
      end
    end
  end
end
