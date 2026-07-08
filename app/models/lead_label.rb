class LeadLabel < ApplicationRecord
  include TenantScoped

  # Tons do design system disponíveis (ax-badge--*). São as cores oferecidas
  # no seletor do catálogo de etiquetas. Além delas, aceita-se cor livre em
  # hexadecimal (#rrggbb) escolhida no color picker do gerenciador.
  COLORS = %w[red amber green blue cyan purple gray].freeze
  HEX_COLOR = /\A#\h{6}\z/

  # Catálogo padrão semeado no primeiro uso de cada corretor. Reflete o
  # propósito do CRM imobiliário (temperatura + perfil do lead) e permanece
  # 100% editável/removível pelo dono.
  DEFAULTS = [
    { name: "Quente",     color: "red" },
    { name: "Morno",      color: "amber" },
    { name: "Frio",       color: "cyan" },
    { name: "Investidor", color: "purple" },
    { name: "VIP",        color: "purple" }
  ].freeze

  belongs_to :admin_user

  has_many :lead_labelings, dependent: :destroy
  has_many :leads, through: :lead_labelings

  validates :name, presence: true, length: { maximum: 40 }
  validates :name, uniqueness: { scope: :admin_user_id, case_sensitive: false }
  validates :color, inclusion: { in: COLORS }, unless: :custom_color?
  validates :color, format: { with: HEX_COLOR, message: "personalizada inválida" }, if: :custom_color?

  scope :ordered, -> { order(:position, :name) }
  scope :for_user, ->(admin_user) { where(admin_user: admin_user) }

  before_validation :normalize_name
  before_validation :assign_position, on: :create

  # Garante que o corretor tenha o catálogo inicial. Idempotente: só semeia se
  # o usuário ainda não possui nenhuma etiqueta.
  def self.ensure_defaults_for(admin_user)
    return none if admin_user.blank?
    return for_user(admin_user).ordered if for_user(admin_user).exists?

    DEFAULTS.each_with_index do |attrs, index|
      create!(admin_user: admin_user, tenant: admin_user.tenant, position: index, **attrs)
    end
    for_user(admin_user).ordered
  end

  # Cor livre (hex) escolhida no picker, em vez de um tom do design system.
  def custom_color?
    color.to_s.start_with?("#")
  end

  private

  def normalize_name
    self.name = name.to_s.strip.gsub(/\s+/, " ")
  end

  def assign_position
    self.position ||= (self.class.for_user(admin_user).maximum(:position) || -1) + 1
  end
end
