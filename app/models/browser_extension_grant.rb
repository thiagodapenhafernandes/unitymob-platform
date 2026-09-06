# Concessão limitada à API da extensão. Não é um token Devise/mobile.
class BrowserExtensionGrant < ApplicationRecord
  TERMS_VERSION = "2026-09-06.v3".freeze
  TERMS_TEXT = <<~TEXT.strip.freeze
    Termos de uso e privacidade da extensão Unitymob — piloto de atendimento

    A extensão relaciona o telefone da conversa individual aberta aos leads que você pode acessar na conta Unitymob identificada neste painel. Após seu aceite, esse telefone é enviado à sua Unitymob para a busca. O painel apresenta o lead, os imóveis vinculados e as tarefas disponíveis conforme suas permissões.

    Você poderá criar leads, registrar notas internas, agendar tarefas e compromissos, aplicar ou remover suas etiquetas existentes, relacionar imóveis disponíveis da imobiliária e alterar a etapa do lead, conforme suas permissões, confirmando cada salvamento no painel. Os registros ficam associados à sua conta e ao seu usuário. Novos leads seguem as regras e notificações de cadastro manual do CRM; tarefas seguem os lembretes configurados. A extensão não importa o histórico das conversas nem envia mensagens pelo WhatsApp Web. Use os dados somente para o atendimento autorizado pela sua imobiliária. Não compartilhe seu acesso.

    O acesso dura até oito horas e pode ser revogado em Gerenciar acesso ou Desconectar. Registramos a data e a versão deste aceite associadas ao seu usuário e à conta. A extensão depende do WhatsApp Web e pode ficar indisponível quando ele mudar.

    Ao aceitar, você autoriza esse uso da extensão nesta conta. Se não concordar, desconecte. As políticas gerais da sua conta continuam aplicáveis.
  TEXT
  include TenantScoped

  belongs_to :admin_user
  belongs_to :trusted_device, optional: true
  has_many :operations, class_name: "BrowserExtensionOperation", dependent: :destroy

  def capabilities
    accepted = terms_accepted?
    { read_leads: accepted, create_leads: accepted && admin_user.can?(:create, :leads),
      create_notes: accepted && admin_user.can?(:edit, :leads),
      create_tasks: accepted && admin_user.can?(:manage, :comercial),
      create_appointments: accepted && admin_user.can?(:manage, :comercial),
      manage_labels: accepted && admin_user.can?(:view, :leads),
      link_properties: accepted && admin_user.can?(:view, :leads),
      change_status: accepted && admin_user.can?(:edit, :leads) }
  end

  validates :extension_id, format: { with: /\A[a-p]{32}\z/ }
  validates :challenge_digest, format: { with: /\A[0-9a-f]{64}\z/ }, uniqueness: true
  validates :challenge_expires_at, :expires_at, presence: true
  validate :associations_match_tenant

  def self.enabled_for?(tenant)
    tenant && ENV.fetch("BROWSER_EXTENSION_TENANT_IDS", "").split(",").map(&:strip).include?(tenant.id.to_s)
  end

  def self.allowed_extension?(id)
    id.to_s.match?(/\A[a-p]{32}\z/) && ENV.fetch("BROWSER_EXTENSION_ALLOWED_IDS", "").split(",").map(&:strip).include?(id)
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(value)
  end

  def self.from_token(token)
    return unless token.to_s.match?(/\A[A-Za-z0-9_-]{43}\z/)

    # Credencial externa confiável resolve o tenant; todo recurso posterior é escopado.
    find_by(token_digest: digest(token))
  end

  def accessible?
    return false if revoked_at || expires_at <= Time.current
    return false unless self.class.enabled_for?(tenant) && self.class.allowed_extension?(extension_id)
    return false unless admin_user.active? && admin_user.tenant_id == tenant_id && !admin_user.system_admin?
    return false unless admin_user.can?(:view, :leads)
    return false if admin_user.two_factor_required? && !admin_user.otp_enabled?
    return false unless admin_user.login_identity.active?
    return true unless admin_user.mirror?

    AccountMembership.where(tenant_id: tenant_id, member_admin_user_id: admin_user_id, status: :active).exists?
  end

  def exchange!
    with_lock do
      return if exchanged_at || challenge_expires_at <= Time.current || !accessible?

      token = SecureRandom.urlsafe_base64(32)
      update!(token_digest: self.class.digest(token), exchanged_at: Time.current)
      token
    end
  end

  def terms_accepted?
    terms_accepted_at.present? && terms_version == TERMS_VERSION && terms_digest == self.class.digest(TERMS_TEXT)
  end

  private

  def associations_match_tenant
    errors.add(:admin_user, "deve pertencer à conta") unless admin_user&.tenant_id == tenant_id
    return unless trusted_device
    return if trusted_device.tenant_id == tenant_id && trusted_device.admin_user_id == admin_user_id

    errors.add(:trusted_device, "deve pertencer ao usuário e à conta")
  end
end
