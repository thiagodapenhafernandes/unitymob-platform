# frozen_string_literal: true

# Endpoint mínimo para o app mobile validar o token logo após o login e
# saber com qual conta/tenant está falando.
module Api
  module V1
    module Field
      class MeController < BaseController
        def show
          render json: {
            admin_user: { id: current_admin_user.id, name: current_admin_user.name, email: current_admin_user.email },
            tenant: { id: current_tenant.id, name: current_tenant.name }
          }
        end
      end
    end
  end
end
