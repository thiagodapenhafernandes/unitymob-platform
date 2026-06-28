class AdminUser < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:facebook]

  has_one_attached :avatar

  belongs_to :profile, optional: true
  belongs_to :manager, class_name: "AdminUser", optional: true
  has_many :subordinates, class_name: "AdminUser", foreign_key: "manager_id"
  has_many :habitations
  has_many :habitation_exports, dependent: :destroy
  has_many :habitation_share_links, dependent: :destroy
  has_one :inbound_webhook_token, dependent: :destroy
  has_many :habitation_audit_logs
  has_many :access_audit_logs
  has_many :data_export_audit_logs
  has_many :lead_audit_logs
  has_many :trusted_devices, dependent: :destroy
  has_many :access_control_rules, dependent: :nullify
  has_many :created_whatsapp_campaigns, class_name: "WhatsappCampaign", foreign_key: "created_by_id", dependent: :restrict_with_error

  # Field ops (check-in geolocalizado)
  belongs_to :default_store, class_name: "Store", optional: true
  has_many :store_shifts, dependent: :destroy
  has_many :store_shift_stores, -> { distinct }, through: :store_shifts, source: :store
  has_many :directed_stores, class_name: "Store", foreign_key: :director_admin_user_id, dependent: :nullify
  has_many :check_ins, dependent: :destroy
  has_one :active_check_in, -> { where(status: :active) }, class_name: "CheckIn"

  enum role: { editor: 0, admin: 1 }
  enum acting_type: { sales: 0, rentals: 1, both: 2 }

  # Admins do Sistema são operadores acima da conta: não aparecem nas listas/organograma/site da conta.
  scope :account_members, -> { where(super_admin: false) }
  scope :active,   -> { account_members.where(active: true) }
  scope :inactive, -> { account_members.where(active: false) }
  scope :displayed_on_site, -> { account_members.where(display_on_site: true) }

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  
  # Admin do Sistema (operador da aplicação) está acima do Admin da Conta: tem todos os
  # poderes de admin + acesso ao painel de sistema. É flag, não perfil/organograma.
  def system_admin?
    super_admin?
  end

  def admin?
    super_admin? || role == 'admin' || profile&.admin?
  end

  def can?(action, resource)
    return true if admin?
    return false unless profile
    profile.can?(action, resource)
  end

  # "own" — só os próprios / "team" — próprios + subárvore de gestão / "all" — tudo
  def scope_for(resource)
    return "all" if admin?
    profile&.scope_for(resource) || "own"
  end

  def owns_all?(resource)
    scope_for(resource) == "all"
  end

  # Perfil enxerga a equipe (subárvore de gestão) para o recurso?
  def can_view_team?(resource)
    scope_for(resource) == "team"
  end

  # IDs do próprio usuário + toda a subárvore de gestão (equipe), usado no escopo "team".
  def team_scope_ids
    @team_scope_ids ||= [id] + descendant_ids
  end

  def subordinate_ids
    @subordinate_ids ||= [id] + subordinates.pluck(:id)
  end

  # Todos os descendentes (recursivo) na árvore de gestão — não inclui o próprio.
  def descendant_ids
    sql = <<~SQL
      WITH RECURSIVE subtree AS (
        SELECT id FROM admin_users WHERE manager_id = #{id.to_i}
        UNION ALL
        SELECT a.id FROM admin_users a JOIN subtree s ON a.manager_id = s.id
      )
      SELECT id FROM subtree
    SQL
    self.class.connection.select_values(sql).map(&:to_i)
  end

  # Conta descendentes por nível imediato (diretos) e total.
  def direct_subordinates_count
    subordinates.size
  end

  def total_descendants_count
    descendant_ids.size
  end
end
