require "rails_helper"

RSpec.describe "Admin password reset MFA assurance", type: :request do
  before { host! "localhost" }

  def reset_token_for(user)
    raw, hashed = Devise.token_generator.generate(AdminUser, :reset_password_token)
    user.update_columns(reset_password_token: hashed, reset_password_sent_at: Time.current)
    raw
  end

  def enable_totp!(user)
    user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
  end

  context "with a TOTP-enabled account" do
    let(:admin) { create(:admin_user, email: "reset-mfa-#{SecureRandom.hex(8)}@salute.test") }

    before { enable_totp!(admin) }

    it "resets the password without signing in and requires the TOTP challenge" do
      raw = reset_token_for(admin)

      put admin_user_password_path, params: {
        admin_user: {
          reset_password_token: raw,
          password: "nova-senha-123",
          password_confirmation: "nova-senha-123"
        }
      }

      expect(response).to redirect_to(admin_two_factor_path)
      expect(admin.reload.valid_password?("nova-senha-123")).to be(true)

      # Sem sessão de vítima: área admin continua exigindo autenticação.
      get admin_root_path
      expect(response).to redirect_to(new_admin_user_session_path)

      # O desafio TOTP pendente aceita um código válido e só então loga.
      code = ROTP::TOTP.new(admin.otp_secret).now
      post admin_two_factor_path, params: { otp_code: code }
      expect(response).to redirect_to(admin_root_path)

      # Sessão autenticada após o segundo fator (login renderiza redirect).
      get new_admin_user_session_path
      expect(response).to redirect_to(admin_root_path)
    end
  end

  context "without TOTP enabled" do
    let(:admin) { create(:admin_user, email: "reset-plain-#{SecureRandom.hex(8)}@salute.test") }

    it "resets the password without signing in and returns to the login page" do
      raw = reset_token_for(admin)

      put admin_user_password_path, params: {
        admin_user: {
          reset_password_token: raw,
          password: "nova-senha-123",
          password_confirmation: "nova-senha-123"
        }
      }

      expect(response).to redirect_to(new_admin_user_session_path)
      expect(admin.reload.valid_password?("nova-senha-123")).to be(true)

      get admin_root_path
      expect(response).to redirect_to(new_admin_user_session_path)

      # Login normal com a nova senha continua funcionando.
      post admin_user_session_path, params: {
        admin_user: { email: admin.email, password: "nova-senha-123" }
      }
      expect(response).to redirect_to(admin_root_path)

      get new_admin_user_session_path
      expect(response).to redirect_to(admin_root_path)
    end
  end
end
