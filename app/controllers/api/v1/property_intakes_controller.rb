module Api
  module V1
    class PropertyIntakesController < PropertyIntakeIntegrationController

      def create
        return head :unsupported_media_type unless request.media_type == "application/json"
        return head :payload_too_large if request.raw_post.bytesize > 128.kilobytes

        payload = JSON.parse(request.raw_post)
        receipt, created = Current.set(tenant: @intake_tenant) do
          Habitations::ExternalIntake.new(@intake_tenant, payload).call
        end
        render json: { protocolo: receipt.protocol, external_id: receipt.external_id, status: "pendente_revisao" },
               status: created ? :created : :ok
      rescue JSON::ParserError
        render json: { error: "JSON inválido" }, status: :bad_request
      rescue Habitations::ExternalIntake::Invalid => error
        render json: { error: error.message }, status: :unprocessable_entity
      rescue Habitations::ExternalIntake::Conflict
        render json: { error: "external_id já recebido com dados diferentes" }, status: :conflict
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: "Cadastro inválido", fields: error.record.errors.attribute_names },
               status: :unprocessable_entity
      end
    end
  end
end
