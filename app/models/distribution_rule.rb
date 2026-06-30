class DistributionRule < ApplicationRecord
  include TenantScoped

  after_initialize :set_defaults

  has_many :distribution_rule_agents, dependent: :destroy
  has_many :admin_users, through: :distribution_rule_agents
  accepts_nested_attributes_for :distribution_rule_agents, allow_destroy: true

  belongs_to :checkin_store, class_name: "Store", optional: true # legado — mantido pra retrocompat de URL/relatórios

  enum :business_type, { venda: 0, locacao: 1, ambos: 2 }, suffix: true
  enum :distribution_mode, { rotary: 0, performance: 1, shark_tank: 2 }

  validates :name, presence: true
  validates :min_price, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :max_price, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validate :max_price_greater_than_min_price
  validates :pocket_time, numericality: { greater_than: 0 }, if: :pocket_active?

  scope :active, -> { where(active: true) }

  def eligible_admin_users_scope
    tenant.admin_users.active.where.not(profile_id: nil)
  end

  def eligible_distribution_agent?(admin_user)
    admin_user.present? &&
      admin_user.tenant_id == tenant_id &&
      admin_user.active? &&
      admin_user.profile&.vertical?
  end

  def eligible_distribution_rule_agents(candidates = distribution_rule_agents)
    if candidates.respond_to?(:joins)
      candidates
        .joins(admin_user: :profile)
        .where(tenant_id: tenant_id)
        .where(admin_users: { tenant_id: tenant_id, active: true, super_admin: false })
        .where(profiles: { tenant_id: tenant_id, axis: Profile::AXES[:vertical] })
    else
      candidates.select { |candidate| eligible_distribution_agent?(candidate.admin_user) }
    end
  end

  def self.pocket_requires_secure_push?
    setting = LeadSetting.instance
    setting.secure_links_enabled? && setting.secure_link_push?
  rescue ActiveRecord::StatementInvalid
    false
  end

  def pocket_operational?
    pocket_active? && pocket_time.to_i.positive? && self.class.pocket_requires_secure_push?
  end

  def next_available_agent(candidates = nil)
    candidates = eligible_distribution_rule_agents(candidates || distribution_rule_agents)
    if rotary?
      if candidates.respond_to?(:order)
        candidates.order(position: :asc, last_lead_received_at: :asc).first
      else
        candidates.min_by { |dra| [ dra.position.to_i, dra.last_lead_received_at || Time.at(0) ] }
      end
    elsif performance?
      candidates.to_a.max_by { |dra| rand ** (1.0 / dra.weight) }
    else
      nil # Shark Tank doesn't have a "next" individual agent upfront
    end
  end

  # Lista consolidada de IDs de loja para o filtro de check-in.
  # Aceita o array novo (checkin_store_ids) e o legado (checkin_store_id).
  def checkin_store_id_list
    ids = Array(checkin_store_ids).compact.reject { |i| i.to_i.zero? }
    ids << checkin_store_id if checkin_store_id.present? && ids.exclude?(checkin_store_id)
    ids.map(&:to_i).uniq
  end

  # Filtra candidatos pelas regras de check-in geolocalizado.
  # Com flags default false, retorna a relation original (retrocompatibilidade total).
  #
  # Flags aplicadas (em cascata):
  #   require_active_checkin      — precisa ter CheckIn com status=active
  #   checkin_store_ids (opcional) — restringe a uma ou mais lojas
  #   exclude_suspicious_checkins — pula check-ins flaggeados pelo antifraude
  #   require_inside_radius       — precisa estar dentro do raio AGORA
  #                                 (out_of_radius_since IS NULL)
  #   require_active_shift        — turno vinculado ao check-in precisa estar ativo
  #                                 AGORA; se check-in manual sem turno, exige um
  #                                 turno ativo do corretor naquela loja.
  def candidates_filtered_by_checkin
    eligible_agents = eligible_distribution_rule_agents
    return eligible_agents unless require_active_checkin?

    scope = tenant.check_ins.where(status: :active)
    store_ids = checkin_store_id_list
    scope = scope.where(store_id: store_ids) if store_ids.any?
    scope = scope.where(suspicious: false) if exclude_suspicious_checkins?
    scope = scope.where(out_of_radius_since: nil) if require_inside_radius?

    scope = scope.includes(:store_shift, :admin_user)

    eligible_user_ids = scope.select { |ci| shift_ok?(ci) }.map(&:admin_user_id)
    eligible_agents.where(admin_user_id: eligible_user_ids)
  end

  # URLs de webhook externo desta regra (config no form, multi-valor).
  # Mantém retrocompat com o campo legado de URL única (webhook_url).
  def notify_webhook_url_list
    urls = Array(notify_webhook_urls).map { |u| u.to_s.strip }
    urls << webhook_url.to_s.strip if webhook_url.present?
    urls.reject(&:blank?).uniq
  end

  def rotate_queue!(just_served_admin_user_id)
    return unless rotary?

    served = distribution_rule_agents.find_by(tenant_id: tenant_id, admin_user_id: just_served_admin_user_id)
    return unless served

    max_pos = distribution_rule_agents.where(tenant_id: tenant_id).maximum(:position) || 0
    served.update(position: max_pos + 1, last_lead_received_at: Time.current)
  end

  def mark_agent_served!(admin_user_id)
    distribution_rule_agents
      .where(tenant_id: tenant_id, admin_user_id: admin_user_id)
      .update_all(last_lead_received_at: Time.current, updated_at: Time.current)
  end

  DAYS = %w[mon tue wed thu fri sat sun]

  def ensure_full_schedule
    self.represamento_schedule ||= {}
    DAYS.each do |day|
      self.represamento_schedule[day] ||= { "active" => "false", "start" => "09:00", "end" => "18:00" }
    end
  end

  private

  def set_defaults
    self.custom_filters ||= []
    self.meta_forms ||= []
    self.notify_webhook_urls ||= []
    ensure_full_schedule
  end

  def shift_ok?(check_in)
    return true unless require_active_shift?

    if check_in.store_shift_id.present?
      check_in.store_shift&.active_at?(Time.current)
    else
      # Check-in manual (sem turno vinculado) — busca qualquer turno ativo
      # do corretor naquela loja, dia e horário atuais.
      now_store_tz = Time.current.in_time_zone(check_in.store.timezone_obj)
      check_in.admin_user.store_shifts
              .where(store_id: check_in.store_id, active: true, day_of_week: now_store_tz.wday)
              .any? { |s| s.active_at?(Time.current) }
    end
  end

  def max_price_greater_than_min_price
    return if min_price.blank? || max_price.blank?
    if max_price < min_price
      errors.add(:max_price, "deve ser maior ou igual ao preço mínimo")
    end
  end
end
