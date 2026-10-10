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

          unless admin_user&.active_for_authentication? && admin_user.valid_password?(params[:password].to_s)
            return render json: { error: "invalid_credentials" }, status: :unauthorized
          end

          if admin_user.mirror?
            return render json: { error: "mirror_account_not_supported" }, status: :unprocessable_entity
          end

          # Conta com TOTP ativo: emite desafio curto em vez do JWT pleno —
          # o app confirma o código em sessions#verify (espelha o desafio web).
          if admin_user.otp_enabled?
            return render json: { status: "challenge_required",
                                  challenge_token: MfaStepUp.issue_challenge(admin_user),
                                  methods: %w[totp backup_code],
                                  expires_in: MfaStepUp::LIFETIME.to_i },
                                status: :ok
          end

          # Conta exige 2FA e o usuário nunca ativou o TOTP: emite matrícula
          # guiada em vez do JWT pleno — o app exibe o QR/chave e confirma o
          # primeiro código em sessions#verify (espelha two_factor_settings).
          if admin_user.two_factor_required? && !admin_user.otp_enabled?
            token, secret = MfaStepUp.issue_enrollment(admin_user)
            provisioning_uri = ROTP::TOTP.new(secret, issuer: admin_user.otp_issuer).provisioning_uri(admin_user.email)
            return render json: { status: "enrollment_required",
                                  enrollment_token: token,
                                  provisioning_uri: provisioning_uri,
                                  manual_key: secret,
                                  issuer: admin_user.otp_issuer,
                                  expires_in: MfaStepUp::LIFETIME.to_i },
                                status: :ok
          end

          access_result = AccessControl::Policy.call(admin_user: admin_user, request: request, controller: self)
          unless access_result.allowed?
            return render json: { error: "access_denied", reason: access_result.reason }, status: :forbidden
          end

          token, = Warden::JWTAuth::UserEncoder.new.call(admin_user, :admin_user, nil)
          render json: { status: "ok", token: token, admin_user: admin_user_payload(admin_user) }, status: :ok
        end

        # Confirma o segundo fator do login guiado (desafio ou matrícula) e,
        # só então, emite o JWT pleno de 30 dias. O token de step-up é curto,
        # unifinalidade e rejeitado pela cadeia operacional (chave dedicada).
        def verify
          step_up = MfaStepUp.decode(params[:token].to_s)
          if step_up.nil?
            return render json: { error: "invalid_token",
                                  message: "Sessão de verificação expirada ou inválida. Entre novamente." },
                                status: :unprocessable_entity
          end
          admin_user = step_up.user

          unless admin_user.active_for_authentication?
            return render json: { error: "invalid_credentials" }, status: :unauthorized
          end

          if MfaStepUp.attempts_exceeded?(admin_user)
            AccessAuditLog.log!(event_type: "two_factor_failed", result: "denied", request: request,
                                admin_user: admin_user, reason: "Tentativas de código esgotadas no app",
                                metadata: { area: "api_mobile" })
            return render json: { error: "too_many_attempts",
                                  message: "Muitas tentativas de código. Entre novamente." },
                                status: :too_many_requests
          end

          access_result = AccessControl::Policy.call(admin_user: admin_user, request: request, controller: self)
          unless access_result.allowed?
            return render json: { error: "access_denied", reason: access_result.reason }, status: :forbidden
          end

          if step_up.purpose == MfaStepUp::ENROLLMENT_PURPOSE
            verify_enrollment(admin_user, step_up)
          else
            verify_challenge(admin_user)
          end
        end

        def destroy
          current_admin_user.update_column(:jti, SecureRandom.uuid)
          head :no_content
        end

        private

        def verify_enrollment(admin_user, step_up)
          secret = step_up.payload["setup_secret"].to_s
          code = params[:code].to_s.gsub(/\s+/, "")
          unless ROTP::TOTP.new(secret).verify(code, drift_behind: 30)
            return invalid_code(admin_user)
          end

          backup_codes = nil
          admin_user.with_lock do
            admin_user.reload
            if admin_user.otp_enabled?
              return render json: { error: "already_enrolled",
                                    message: "Verificação já concluída. Entre novamente." },
                                  status: :unprocessable_entity
            end

            admin_user.update!(otp_secret: secret, otp_enabled_at: Time.current)
            backup_codes = admin_user.generate_backup_codes!
          end
          AccessAuditLog.log!(event_type: "two_factor_enabled", result: "allowed", request: request,
                              admin_user: admin_user, reason: "2FA ativado pelo app mobile",
                              metadata: { area: "api_mobile" })
          issue_full_token(admin_user, backup_codes: backup_codes)
        end

        def verify_challenge(admin_user)
          code = params[:code].to_s
          backup = code.gsub(/\s+/, "").length >= 10
          if admin_user.verify_totp!(code) || (backup && admin_user.verify_backup_code!(code))
            metadata = { area: "api_mobile" }
            metadata[:backup_code] = true if backup
            AccessAuditLog.log!(event_type: "two_factor_success", result: "allowed", request: request,
                                admin_user: admin_user, reason: "Código TOTP válido no app",
                                metadata: metadata)
            issue_full_token(admin_user)
          else
            invalid_code(admin_user)
          end
        end

        def invalid_code(admin_user)
          MfaStepUp.record_failure(admin_user)
          AccessAuditLog.log!(event_type: "two_factor_failed", result: "denied", request: request,
                              admin_user: admin_user, reason: "Código TOTP inválido no app",
                              metadata: { area: "api_mobile" })
          render json: { error: "invalid_code",
                         message: "Código inválido. Confira o aplicativo autenticador." },
                       status: :unprocessable_entity
        end

        def issue_full_token(admin_user, backup_codes: nil)
          token, = Warden::JWTAuth::UserEncoder.new.call(admin_user, :admin_user, nil)
          payload = { status: "ok", token: token, admin_user: admin_user_payload(admin_user) }
          payload[:backup_codes] = backup_codes if backup_codes
          render json: payload, status: :ok
        end

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
