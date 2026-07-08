class DistributionRule < ApplicationRecord
  include TenantScoped

  AUTO_UPDATE_TRIGGERS = %w[sorteio pos_risca fora_horario].freeze
  AUTO_UPDATE_TRIGGER_LABELS = {
    "sorteio" => "Logo após check-in de entrada",
    "pos_risca" => "Logo após check-in pós-risca",
    "fora_horario" => "Logo após check-in fora da roleta"
  }.freeze
  AUTO_UPDATE_TRIGGER_ALIASES = {
    "entrada" => "sorteio",
    "sorteio" => "sorteio",
    "pos_risca" => "pos_risca",
    "pos-risca" => "pos_risca",
    "fora_roleta" => "fora_horario",
    "fora_horario" => "fora_horario",
    "fora_hora" => "fora_horario"
  }.freeze

  after_initialize :set_defaults
  before_validation :ensure_auto_update_trigger_value, if: :has_auto_update_trigger_column?

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
  validate :validate_auto_update_triggers, if: :has_auto_update_trigger_column?

  scope :active, -> { where(active: true) }

  def eligible_admin_users_scope
    tenant.admin_users.active.where.not(profile_id: nil)
  end

  def eligible_distribution_agent?(admin_user)
    admin_user.present? &&
      admin_user.tenant_id == tenant_id &&
      admin_user.active? &&
      admin_user.profile&.vertical? &&
      !admin_user.profile&.tenant_owner?
  end

  def eligible_distribution_rule_agents(candidates = distribution_rule_agents)
    if candidates.respond_to?(:joins)
      # dono da conta nunca entra no rodizio (mesmo se salvo em regra antiga)
      candidates
        .joins(admin_user: :profile)
        .where(tenant_id: tenant_id)
        .where(admin_users: { tenant_id: tenant_id, active: true, super_admin: false })
        .where(profiles: { tenant_id: tenant_id, axis: Profile::AXES[:vertical] })
        .where.not(profiles: { key: "tenant_owner" })
    else
      candidates.select { |candidate| eligible_distribution_agent?(candidate.admin_user) }
    end
  end

  # ---- Gate de canal de notificação (a regra só marca canal DISPONÍVEL) -------
  # Disponível = tenant tem o PRÓPRIO configurado OU (tenant opt-in E global
  # configurado). Usa o TransportResolver/EmailSetting.for pra não duplicar a
  # regra de fallback. Tolerante: sem tenant no contexto, considera indisponível.

  def whatsapp_channel_available?
    gate_tenant = tenant.presence || Current.tenant
    return false if gate_tenant.blank?

    Notifications::TransportResolver.whatsapp(gate_tenant).present?
  rescue StandardError => e
    Rails.logger.warn("[DistributionRule] gate whatsapp indisponivel: #{e.message}")
    false
  end

  def email_channel_available?
    gate_tenant = tenant.presence || Current.tenant
    EmailSetting.for(gate_tenant).present?
  rescue StandardError => e
    Rails.logger.warn("[DistributionRule] gate email indisponivel: #{e.message}")
    false
  end

  # Disponibilidade por chave de canal (:whatsapp/:email/:push) — push/webhook
  # inalterados (push via PushSetting global; webhook validado inline no form).
  def notification_channel_available?(channel)
    case channel.to_sym
    when :whatsapp then whatsapp_channel_available?
    when :email then email_channel_available?
    when :push then PushSetting.instance.configured?
    else true
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

  def self.auto_update_trigger_options
    AUTO_UPDATE_TRIGGERS.map { |trigger| [AUTO_UPDATE_TRIGGER_LABELS.fetch(trigger), trigger] }
  end

  def auto_update_agents_enabled?
    has_attribute?(:auto_update_agents_enabled) && !!self[:auto_update_agents_enabled]
  end

  def auto_update_shuffle_agents?
    has_attribute?(:auto_update_shuffle_agents) && !!self[:auto_update_shuffle_agents]
  end

  def auto_update_trigger
    return ["sorteio"] unless has_auto_update_trigger_column?

    normalize_auto_update_trigger_values(read_attribute(:auto_update_trigger)).presence || ["sorteio"]
  end

  def auto_update_trigger=(value)
    return unless has_auto_update_trigger_column?

    write_attribute(:auto_update_trigger, normalize_auto_update_trigger_values(value))
  end

  def auto_update_trigger_label
    auto_update_trigger.map { |trigger| AUTO_UPDATE_TRIGGER_LABELS.fetch(trigger, trigger.humanize) }.to_sentence(two_words_connector: " e ", last_word_connector: " e ")
  end

  def update_agents_from_store_checkin!(status: nil, date: Date.current)
    return false unless auto_update_agents_enabled?

    store_ids = checkin_store_id_list
    return false if store_ids.blank?

    statuses = normalize_auto_update_trigger_values(status.presence || auto_update_trigger)
    statuses = auto_update_trigger if statuses.blank?
    checkins = tenant.check_ins
                    .where(store_id: store_ids, checked_in_at: date.all_day)
                    .for_arrival_statuses(statuses)
                    .includes(:admin_user)
                    .order(:checked_in_at, :id)
                    .to_a

    selected_users = interleaved_checked_in_agents(checkins, store_ids)
    selected_users = selected_users.shuffle if auto_update_shuffle_agents?

    eligible_ids = eligible_admin_users_scope.where(id: selected_users.map(&:id)).pluck(:id)
    selected_ids = selected_users.map(&:id).select { |id| eligible_ids.include?(id) }.uniq

    transaction do
      current_agents = distribution_rule_agents.index_by(&:admin_user_id)

      current_agents.each do |admin_user_id, agent|
        agent.destroy! unless selected_ids.include?(admin_user_id)
      end

      selected_ids.each_with_index do |admin_user_id, index|
        agent = current_agents[admin_user_id] || distribution_rule_agents.build(admin_user_id: admin_user_id)
        agent.tenant = tenant if agent.respond_to?(:tenant=)
        agent.position = index + 1
        agent.weight = agent.weight.presence || 1
        agent.save! if agent.new_record? || agent.changed?
      end
    end

    true
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

    scope = scope.includes(:store, :admin_user)

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

  # Namespace (classid) do advisory lock do rodízio — exclusivo desta feature.
  ROTATION_ADVISORY_LOCK_KEY = 762_501

  # Serializa seleção+rotação do rodízio entre processos concorrentes (threads
  # do Puma e do SolidQueue) com advisory lock transacional por regra — sem
  # FOR UPDATE na linha, pra não esbarrar nos defaults do after_initialize.
  # Transação curta: nunca coloque chamadas externas (HTTP/notificação) aqui.
  def with_rotation_lock
    return yield unless rotary?

    self.class.transaction do
      self.class.connection.execute(
        "SELECT pg_advisory_xact_lock(#{ROTATION_ADVISORY_LOCK_KEY}, #{id.to_i})"
      )
      yield
    end
  end

  # Deve rodar dentro de with_rotation_lock: faz read-modify-write de position.
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
    self.auto_update_trigger = ["sorteio"] if has_auto_update_trigger_column? && read_attribute(:auto_update_trigger).blank?
  end

  def shift_ok?(check_in)
    return true unless require_active_shift?

    check_in.store&.operational_shift_active_at?(Time.current)
  end

  def has_auto_update_trigger_column?
    has_attribute?(:auto_update_trigger)
  end

  def normalize_auto_update_trigger_values(value)
    raw_values = case value
                 when Array then value
                 when String then value.split(",")
                 else Array(value)
                 end

    raw_values.filter_map do |raw|
      token = raw.to_s.strip.downcase.tr(" ", "_")
      AUTO_UPDATE_TRIGGER_ALIASES[token].presence_in(AUTO_UPDATE_TRIGGERS)
    end.uniq
  end

  def ensure_auto_update_trigger_value
    self.auto_update_trigger = auto_update_trigger.presence || ["sorteio"]
  end

  def validate_auto_update_triggers
    invalid_values = Array(read_attribute(:auto_update_trigger)).reject { |value| AUTO_UPDATE_TRIGGERS.include?(value.to_s) }
    return if invalid_values.empty?

    errors.add(:auto_update_trigger, "contém valores inválidos: #{invalid_values.join(', ')}")
  end

  def interleaved_checked_in_agents(checkins, store_ids)
    grouped = checkins.group_by(&:store_id).transform_values do |store_checkins|
      store_checkins.map(&:admin_user).compact.uniq(&:id)
    end

    result = []
    loop do
      added = false
      store_ids.each do |store_id|
        agent = grouped[store_id]&.shift
        next if agent.blank?

        result << agent
        added = true
      end
      break unless added
    end
    result
  end

  def max_price_greater_than_min_price
    return if min_price.blank? || max_price.blank?
    if max_price < min_price
      errors.add(:max_price, "deve ser maior ou igual ao preço mínimo")
    end
  end
end
