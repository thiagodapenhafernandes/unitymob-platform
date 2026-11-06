module Api
  module V1
    class PropertyIntakesController < ActionController::API
      def create
        token = request.authorization.to_s[/\ABearer ([a-f0-9]{64})\z/i, 1]
        tenant = Tenant.active.find_by(property_intake_token_digest: Digest::SHA256.hexdigest(token)) if token
        return head :unauthorized unless tenant

        return head :unsupported_media_type unless request.media_type == "application/json"
        return head :payload_too_large if request.raw_post.bytesize > 128.kilobytes

        payload = JSON.parse(request.raw_post)
        receipt, created = Current.set(tenant: tenant) do
          Habitations::ExternalIntake.new(tenant, payload).call
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
