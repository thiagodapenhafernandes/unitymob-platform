# Convite/participação de um usuário externo em OUTRA conta (multi-conta,
# modelo agência). No aceite, nasce um admin_user ESPELHO no tenant convidado
# (AccountMemberships::AcceptService); o snapshot de acesso vem do convite.
class AccountMembership < ApplicationRecord
  include TenantScoped

  INVITE_VALIDITY = 7.days

  belongs_to :tenant
  belongs_to :primary_admin_user, class_name: "AdminUser", optional: true
  belongs_to :member_admin_user, class_name: "AdminUser", optional: true
  belongs_to :profile
  belongs_to :horizontal_profile, class_name: "Profile", optional: true
  belongs_to :manager, class_name: "AdminUser", optional: true
  belongs_to :rentals_manager, class_name: "AdminUser", optional: true
  belongs_to :invited_by, class_name: "AdminUser"
  belongs_to :revoked_by, class_name: "AdminUser", optional: true

  enum :status, { invited: 0, active: 1, revoked: 2 }

  validates :invited_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :profile_belongs_to_tenant
  validate :profile_cannot_be_tenant_owner
  validate :invited_email_not_already_member, if: -> { new_record? || invited_email_changed? }

  scope :live, -> { where.not(status: :revoked) }

  # Token cru vai só no e-mail; o banco guarda o digest.
  def generate_invite_token!
    raw = SecureRandom.urlsafe_base64(32)
    update!(
      invite_token_digest: self.class.digest_token(raw),
      invite_sent_at: Time.current,
      invite_expires_at: INVITE_VALIDITY.from_now
    )
    raw
  end

  def self.find_by_raw_token(raw)
    return nil if raw.blank?

    find_by(invite_token_digest: digest_token(raw))
  end

  def self.digest_token(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def invite_expired?
    invite_expires_at.blank? || invite_expires_at < Time.current
  end

  def revoke!(by:)
    transaction do
      update!(status: :revoked, revoked_at: Time.current, revoked_by: by)
      # update! (bang): se a validação do espelho falhar, a exceção aborta a
      # transação inteira — sem revogação "meia-boca" que mantém acesso cross-tenant.
      member_admin_user&.update!(active: false)
      # Solta o vínculo do espelho: o índice único member_admin_user_id é GLOBAL;
      # sem nular, re-convidar a mesma pessoa reusaria o espelho e colidiria no
      # aceite. Postgres aceita múltiplos NULL no unique; histórico fica em
      # revoked_at/revoked_by. O espelho já foi desativado acima.
      update!(member_admin_user_id: nil) if member_admin_user_id.present?
    end
  end

  private

  def profile_belongs_to_tenant
    return if profile.blank? || tenant.blank?

    errors.add(:profile, "deve pertencer à conta que convida") if profile.tenant_id != tenant_id
    if horizontal_profile.present? && horizontal_profile.tenant_id != tenant_id
      errors.add(:horizontal_profile, "deve pertencer à conta que convida")
    end
  end

  # O topo da conta é único e intransferível — convite nunca entrega a conta.
  def profile_cannot_be_tenant_owner
    errors.add(:profile, "não pode ser o perfil de Admin da Conta") if profile&.tenant_owner?
  end

  def invited_email_not_already_member
    return if invited_email.blank? || tenant.blank?

    normalized = invited_email.to_s.strip.downcase
    scope = tenant.admin_users
    exists =
      if AdminUser.column_names.include?("contact_email")
        scope.where("lower(email) = :email OR lower(contact_email) = :email", email: normalized).exists?
      else
        scope.where("lower(email) = ?", normalized).exists?
      end
    errors.add(:invited_email, "já é usuário desta conta") if exists
  end
end
