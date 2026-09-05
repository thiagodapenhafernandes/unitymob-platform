class Staff < ActiveRecord::Base
  has_secure_password validations: false
  has_many :staff_sessions
  after_update do
    if saved_change_to_active? || saved_change_to_session_version? || saved_change_to_role?
      staff_sessions.where(ended_at: nil).update_all(ended_at: Time.current, end_reason: 'access_changed')
    end
  end
  encrypts :otp_secret
  ROLE_LABELS = { "admin" => "Admin do sistema", "suporte" => "Suporte", "financeiro" => "Financeiro" }.freeze
  ROLES = %w[admin suporte financeiro].freeze
  validates :name, :email, presence: true
  validates :email, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :verification_method, inclusion: { in: %w[totp email] }
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: 12 }, confirmation: true, allow_nil: true
  before_validation { self.email = email.to_s.strip.downcase }
  def operator? = active? && %w[admin suporte].include?(role)
  def admin? = active? && role == "admin"

  def activation_token!
    token = SecureRandom.urlsafe_base64(32)
    update!(activation_digest: Digest::SHA256.hexdigest(token), activation_expires_at: 1.hour.from_now,
      otp_secret: ROTP::Base32.random, activated_at: nil, otp_consumed_at: nil, session_version: session_version + 1)
    token
  end

  def verify_otp!(code)
    with_lock do
      stamp = ROTP::TOTP.new(otp_secret, issuer: "Unitymob Central").verify(code.to_s, drift_behind: 30, after: otp_consumed_at)
      return false unless stamp
      update!(otp_consumed_at: stamp)
      true
    end
  end
  def email_verification? = verification_method == "email"

  def issue_email_code!
    with_lock do
      return nil if email_code_sent_at && email_code_sent_at > 1.minute.ago
      code = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
      nonce = SecureRandom.urlsafe_base64(32)
      update!(email_code_digest: code_digest(code), email_challenge_digest: Digest::SHA256.hexdigest(nonce),
        email_code_expires_at: 10.minutes.from_now, email_code_sent_at: Time.current, email_code_attempts: 0)
      [code, nonce]
    end
  end

  def verify_email_code!(code, nonce)
    with_lock do
      return false unless active? && activated_at && email_verification? && email_code_expires_at&.future? && email_code_attempts < 5
      return false unless ActiveSupport::SecurityUtils.secure_compare(email_challenge_digest.to_s, Digest::SHA256.hexdigest(nonce.to_s))
      if code.to_s.match?(/\A\d{6}\z/) && ActiveSupport::SecurityUtils.secure_compare(email_code_digest.to_s, code_digest(code))
        update!(email_code_digest: nil, email_challenge_digest: nil, email_code_expires_at: nil, email_code_attempts: 0)
        true
      else
        update!(email_code_attempts: email_code_attempts + 1)
        false
      end
    end
  end

  private

  def code_digest(code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "staff:#{id}:#{code}")
  end

end
