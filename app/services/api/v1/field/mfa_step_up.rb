# frozen_string_literal: true

module Api
  module V1
    module Field
      # Tokens curtos de step-up MFA para o login mobile guiado (desafio TOTP
      # ou matrícula). Assinados com chave dedicada derivada do secret_key_base
      # — NUNCA com o segredo do devise-jwt — então a cadeia operacional Warden
      # não valida esses tokens: eles não autorizam endpoint nenhum além do
      # verify, que os confere manualmente (assinatura, expiração e vínculo).
      #
      # Uso único sem servidor de estado: o token carrega o timestep consumido
      # (challenge) ou exige conta ainda não matriculada (enrollment). Após o
      # sucesso o estado muda e o token morre; tentativas erradas contam em
      # Rails.cache (5 por janela, espelhando o limite da web).
      class MfaStepUp
        CHALLENGE_PURPOSE = "field_mfa_challenge"
        ENROLLMENT_PURPOSE = "field_mfa_enrollment"
        LIFETIME = 5.minutes
        MAX_ATTEMPTS = 5

        Result = Struct.new(:user, :purpose, :payload, keyword_init: true)

        class << self
          def issue_challenge(user)
            mint(sub: user.id, purpose: CHALLENGE_PURPOSE, consumed_timestep: user.otp_consumed_timestep)
          end

          def issue_enrollment(user)
            secret = ROTP::Base32.random
            [mint(sub: user.id, purpose: ENROLLMENT_PURPOSE, setup_secret: secret), secret]
          end

          def decode(token)
            payload, = JWT.decode(token.to_s, signing_key, true, algorithm: "HS256")
            return nil unless [CHALLENGE_PURPOSE, ENROLLMENT_PURPOSE].include?(payload["purpose"])

            user = AdminUser.find_by(id: payload["sub"])
            return nil if user.nil?
            return nil unless state_matches?(user, payload)

            Result.new(user: user, purpose: payload["purpose"], payload: payload)
          rescue JWT::DecodeError
            nil
          end

          def attempts_exceeded?(user)
            Rails.cache.read(counter_key(user)).to_i >= MAX_ATTEMPTS
          end

          def record_failure(user)
            Rails.cache.increment(counter_key(user), 1, expires_in: LIFETIME)
          end

          private

          def signing_key
            Rails.application.key_generator.generate_key("field mfa step-up", 32)
          end

          def mint(claims)
            JWT.encode(claims.merge(exp: LIFETIME.from_now.to_i, jti: SecureRandom.uuid), signing_key, "HS256")
          end

          def state_matches?(user, payload)
            case payload["purpose"]
            when CHALLENGE_PURPOSE
              user.otp_enabled? && user.otp_consumed_timestep == payload["consumed_timestep"]
            when ENROLLMENT_PURPOSE
              !user.otp_enabled? && payload["setup_secret"].present?
            end
          end

          def counter_key(user)
            "field_mfa_failures:#{user.id}"
          end
        end
      end
    end
  end
end
