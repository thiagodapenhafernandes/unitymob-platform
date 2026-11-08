module Api
  module V1
    class PropertyIntakeSearchesController < PropertyIntakeIntegrationController
      def index
        results = Habitations::ExternalIntakeSearch.new(@intake_tenant, params.permit(
          :cep, :logradouro, :numero, :complemento, :cidade, :uf, :torre
        ).to_h).call
        render json: { imoveis: results }
      rescue Habitations::ExternalIntake::Invalid => error
        render json: { error: error.message }, status: :unprocessable_entity
      end
    end
  end
end
