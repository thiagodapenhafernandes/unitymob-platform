# Concessão limitada à API da extensão. Não é um token Devise/mobile.
class BrowserExtensionGrant < ApplicationRecord
  TERMS_VERSION = "2026-09-08.v6".freeze
  TERMS_TEXT = <<~TEXT.strip.freeze
    Uso de dados e termos da extensão Unitymob para WhatsApp

    Para conectar sua conta, tratamos o e-mail informado, a imobiliária escolhida e uma credencial temporária de acesso. Após este aceite, a extensão acessa o nome, o telefone e identificadores técnicos da conversa individual aberta no WhatsApp Web para identificar o contato e conferir o destinatário. O telefone é enviado ao CRM da imobiliária selecionada para buscar somente os leads permitidos ao seu usuário.

    Conforme suas permissões, você pode consultar e criar leads, registrar contatos e notas, organizar tarefas e compromissos, aplicar ou remover etiquetas existentes, alterar a etapa do lead e relacionar imóveis. As alterações que você confirma ficam registradas no CRM, associadas à sua conta e ao seu usuário. Cadastros e tarefas seguem as regras de notificações e lembretes do CRM.

    A extensão não importa o histórico de mensagens do WhatsApp. Os links públicos dos imóveis selecionados são enviados individualmente na conversa atual somente após sua ação e confirmação. Confira os imóveis e o destinatário antes de enviar. Não use o recurso para spam ou contatos indevidos.

    Os dados são usados para essas funcionalidades, segurança e suporte, conforme a Política de Privacidade, pela imobiliária e pelos operadores necessários à prestação do serviço. Não são vendidos nem usados para publicidade personalizada. A credencial fica no armazenamento local do Chrome, não é sincronizada entre navegadores e expira em até oito horas ou, se você marcar “Manter conectado por 30 dias”, em até 30 dias. Você pode revogar o acesso em Gerenciar acesso ou Desconectar. Isso não apaga os registros já criados no CRM; consulte Opções de privacidade para solicitações sobre seus dados.

    Registramos a data e a versão deste aceite com seu usuário e sua conta. Use somente dados de atendimentos autorizados e não compartilhe seu acesso. A extensão depende do WhatsApp Web e pode ficar indisponível quando ele mudar; não é um produto oficial da Meta ou do Google.

    Ao aceitar, você concorda com este uso da extensão nesta conta e com os Termos de Uso. Consulte os links de Política de Privacidade e Opções de privacidade neste painel. Se não concordar, desconecte.
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
    terms_acceptance.present?
  end

  # Expiring/revoking an access token does not undo the user's recorded acceptance.
  # Keep the original record and date; never fabricate a new acceptance on login.
  def terms_acceptance
    digest = self.class.digest(TERMS_TEXT)
    return self if terms_accepted_at.present? && terms_version == TERMS_VERSION && terms_digest == digest
    return unless tenant_id && admin_user_id

    self.class.where(tenant_id: tenant_id, admin_user_id: admin_user_id,
      terms_version: TERMS_VERSION, terms_digest: digest)
      .where.not(terms_accepted_at: nil).order(terms_accepted_at: :desc, id: :desc).first
  end

  private

  def associations_match_tenant
    errors.add(:admin_user, "deve pertencer à conta") unless admin_user&.tenant_id == tenant_id
    return unless trusted_device
    return if trusted_device.tenant_id == tenant_id && trusted_device.admin_user_id == admin_user_id

    errors.add(:trusted_device, "deve pertencer ao usuário e à conta")
  end
end
