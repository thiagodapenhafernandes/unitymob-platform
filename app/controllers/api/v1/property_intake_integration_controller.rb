module Api
  module V1
    class PropertyIntakeIntegrationController < ActionController::API
      before_action :authenticate_integration

      private

      def authenticate_integration
        token = request.authorization.to_s[/\ABearer ([a-f0-9]{64})\z/i, 1]
        @intake_tenant = Tenant.active.find_by(property_intake_token_digest: Digest::SHA256.hexdigest(token)) if token
        head :unauthorized unless @intake_tenant
      end
    end
  end
end
