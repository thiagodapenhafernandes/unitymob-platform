# Cartão de apresentação para o atendimento WhatsApp.
# Dois níveis: TEMPLATE DE SISTEMA (tenant; admin_user nulo + system=true,
# sempre disponível para todos os corretores, não excluível) e cartões PESSOAIS
# do corretor. REGRA DE OURO: o cartão nunca carrega telefone/contato pessoal —
# nome/CRECI/avatar entram dinamicamente na hora do envio, pelo número da empresa.
class PresentationCard < ApplicationRecord
  include TenantScoped

  belongs_to :admin_user, optional: true
  has_many :whatsapp_messages, dependent: :nullify

  validates :label, presence: true, length: { maximum: 40 }
  validates :greeting, presence: true, length: { maximum: 600 }
  validates :admin_user, presence: true, unless: :system?

  scope :ordered, -> { order(system: :desc, position: :asc, id: :asc) }
  scope :active, -> { where(active: true) }
  scope :for_user, ->(admin_user) { where(admin_user: admin_user) }
  scope :system_templates, -> { where(system: true) }
  scope :personal, -> { where(system: false) }

  before_validation :assign_position, on: :create

  DEFAULT_LABEL = "Padrão".freeze
  DEFAULT_GREETING = "Oi! 👋 Aqui é o {nome}, da {empresa}. A partir de agora eu cuido do seu atendimento — pode falar comigo por aqui. Como posso ajudar?".freeze
  LEGACY_DEFAULT_GREETING = "Olá! Sou {nome}, corretor(a) responsável pelo seu atendimento. Como posso ajudar?".freeze

  # Cartões que um corretor pode ENVIAR: templates do sistema + os dele.
  def self.available_for(admin_user)
    return none if admin_user.blank?

    where(tenant_id: admin_user.tenant_id)
      .where("presentation_cards.system = TRUE OR presentation_cards.admin_user_id = ?", admin_user.id)
      .active.ordered
  end

  # Garante o template de sistema do tenant (seed idempotente).
  def self.ensure_system_default_for(tenant)
    return if tenant.blank?
    return if system_templates.where(tenant_id: tenant.id).exists?

    create!(tenant_id: tenant.id, admin_user: nil, system: true,
            label: DEFAULT_LABEL, greeting: DEFAULT_GREETING, use_photo: true, active: true)
  end

  # Saudação com os dados de QUEM envia: {nome}, {creci} e {empresa} (tenant)
  # são resolvidos na hora do envio.
  def greeting_for(admin_user)
    greeting.to_s
            .gsub("{nome}", admin_user&.name.to_s.strip.presence || "o corretor")
            .gsub("{creci}", admin_user&.creci.to_s.strip)
            .gsub("{empresa}", company_display_name)
            .squeeze(" ")
  end

  # Corpo final da mensagem de apresentação. A assinatura "— nome · CRECI" só
  # entra quando a saudação NÃO cita o nome do corretor (evita duplicar).
  # Nunca inclui telefone pessoal (regra de ouro).
  def message_body_for(admin_user)
    text = greeting_for(admin_user).strip
    name = admin_user&.name.to_s.strip

    return text if name.present? && text.downcase.include?(name.downcase)

    signature = ["— #{name.presence || 'Corretor'}", ("CRECI #{admin_user.creci}" if admin_user&.creci.present?)].compact.join(" · ")
    "#{text}\n\n#{signature}"
  end

  # Nome do cliente para {empresa}: o nome de exibição (Identidade e Marca →
  # site_name) vem primeiro; o nome interno da conta é fallback técnico.
  def company_display_name
    display = begin
      LayoutSetting.instance.site_name.to_s.strip.presence
    rescue StandardError
      nil
    end

    display || tenant&.name.to_s.strip.presence || "nossa equipe"
  end

  def editable_by?(admin_user)
    return false if admin_user.blank?
    return admin_user.tenant_owner? if system?

    admin_user_id == admin_user.id
  end

  private

  def assign_position
    self.position ||= 0
    return if position.positive? || system?

    self.position = (self.class.personal.for_user(admin_user).maximum(:position) || -1) + 1
  end
end
