# frozen_string_literal: true

# Login/logout do app mobile: troca email+senha por um JWT (30 dias),
# emitido explicitamente aqui — não depende do hook automático de
# dispatch/revocation do devise-jwt, então nenhum outro fluxo de sign-in
# (admin/PWA web) é afetado por esta configuração.
module Api
  module V1
    module Field
      class SessionsController < ApplicationController
        skip_before_action :verify_authenticity_token, raise: false
        before_action :authenticate_admin_user!, only: :destroy

        def create
          admin_user = AdminUser.find_for_authentication(email: params[:email].to_s)

          unless admin_user&.valid_password?(params[:password].to_s)
            return render json: { error: "invalid_credentials" }, status: :unauthorized
          end

          if admin_user.mirror?
            return render json: { error: "mirror_account_not_supported" }, status: :unprocessable_entity
          end

          # 2FA por app ainda não existe: contas com TOTP obrigatório não
          # conseguem logar pelo mobile até esse fluxo ser construído.
          if admin_user.otp_enabled?
            return render json: { error: "two_factor_required" }, status: :unprocessable_entity
          end

          access_result = AccessControl::Policy.call(admin_user: admin_user, request: request, controller: self)
          unless access_result.allowed?
            return render json: { error: "access_denied", reason: access_result.reason }, status: :forbidden
          end

          token, = Warden::JWTAuth::UserEncoder.new.call(admin_user, :admin_user, nil)
          render json: { token: token, admin_user: admin_user_payload(admin_user) }, status: :ok
        end

        def destroy
          current_admin_user.update_column(:jti, SecureRandom.uuid)
          head :no_content
        end

        private

        def admin_user_payload(admin_user)
          {
            id: admin_user.id,
            name: admin_user.name,
            email: admin_user.email,
            tenant: { id: admin_user.tenant&.id, name: admin_user.tenant&.name }
          }
        end
      end
    end
  end
end
