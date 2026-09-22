class WhatsappResponseFlow < ApplicationRecord
  include TenantScoped

  ACTIONS = {
    "record_only" => "Apenas registrar",
    "send_message" => "Responder com mensagem",
    "send_url" => "Enviar link",
    "create_task" => "Criar tarefa comercial",
    "distribute_lead" => "Enviar para fila/regra",
    "send_to_user" => "Enviar para usuário",
    "run_automation" => "Iniciar automação"
  }.freeze

  # Prazo da tarefa criada por um botão (em minutos a partir do clique).
  TASK_DUE_OPTIONS = {
    30 => "em 30 minutos", 60 => "em 1 hora", 120 => "em 2 horas", 240 => "em 4 horas", 1440 => "em 1 dia", 2880 => "em 2 dias"
  }.freeze
  DEFAULT_TASK_DUE_MINUTES = 120

  HOURS_ACTIONS = %w[send_message distribute_lead send_to_user].freeze
  DAY_KEYS = %w[mon tue wed thu fri sat sun].freeze
  DEFAULT_BUSINESS_HOURS = {
    "enabled" => "0",
    "days" => %w[mon tue wed thu fri],
    "start" => "08:00",
    "end" => "18:00"
  }.freeze
  DEFAULT_AUTO_REPLY_MESSAGE = "Perfeito! 😊 Recebemos sua solicitação. Em instantes, um de nossos atendentes entrará em contato com você para dar continuidade ao atendimento.".freeze
  DEFAULT_OUTSIDE_HOURS_MESSAGE = "Não estamos disponíveis no momento, mas entraremos em contato assim que possível.".freeze

  belongs_to :whatsapp_template
  belongs_to :created_by, class_name: "AdminUser", optional: true
  belongs_to :automation_workflow, optional: true
  has_many :receptive_sender_numbers,
           class_name: "WhatsappSenderNumber",
           foreign_key: :receptive_response_flow_id,
           dependent: :nullify

  validates :name, presence: true
  validates :whatsapp_template_id, uniqueness: { scope: :tenant_id }
  validate :template_belongs_to_tenant
  validate :template_must_be_for_response_flow
  validate :automation_workflow_belongs_to_tenant
  validate :attendance_actions_must_have_target_agent

  before_validation :normalize_button_actions

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(active: :desc, updated_at: :desc) }

  def self.action_options
    ACTIONS.map { |key, label| [label, key] }
  end

  def action_for(button_key:, button_text:)
    actions = button_actions.to_h
    actions[button_key.to_s].presence || actions.values.find { |action| action["button_text"].to_s.casecmp?(button_text.to_s) }
  end

  def business_hours_active?(action, time = Time.zone.now)
    hours = action.to_h.fetch("business_hours", {})
    return true unless ActiveModel::Type::Boolean.new.cast(hours["enabled"])

    day_key = DAY_KEYS[(time.wday + 6) % 7]
    return false unless Array(hours["days"]).map(&:to_s).include?(day_key)

    start_time = Time.zone.parse("#{time.to_date} #{hours['start'].presence || '08:00'}")
    end_time = Time.zone.parse("#{time.to_date} #{hours['end'].presence || '18:00'}")
    return time.between?(start_time, end_time) if start_time <= end_time

    time >= start_time || time <= end_time
  rescue
    true
  end

  private

  def normalize_button_actions
    raw = button_actions.respond_to?(:to_unsafe_h) ? button_actions.to_unsafe_h : button_actions.to_h
    self.button_actions = raw.each_with_object({}) do |(key, value), memo|
      attrs = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
      action = attrs["action"].presence_in(ACTIONS.keys) || "record_only"
      business_hours = attrs.fetch("business_hours", {})
      business_hours = business_hours.to_unsafe_h if business_hours.respond_to?(:to_unsafe_h)
      # target_admin_user_id (singular) é o formato legado; continua aceito.
      target_admin_user_ids = Array(attrs["target_admin_user_ids"].presence || attrs["target_admin_user_id"]).map { |id| id.to_s.strip }.compact_blank.uniq

      memo[key.to_s] = {
        "button_key" => attrs["button_key"].presence || key.to_s,
        "button_text" => attrs["button_text"].to_s.strip,
        "action" => action,
        "message" => default_message_for(action, attrs["message"]),
        "url" => attrs["url"].to_s.strip,
        "distribution_rule_id" => attrs["distribution_rule_id"].to_s.strip,
        "target_admin_user_id" => target_admin_user_ids.first,
        "target_admin_user_ids" => target_admin_user_ids,
        "target_user_id" => attrs["target_user_id"].to_s.strip,
        "task_title" => attrs["task_title"].to_s.strip,
        "task_user_id" => attrs["task_user_id"].to_s.strip,
        "task_due_minutes" => attrs["task_due_minutes"].to_i.then { |minutes| minutes if TASK_DUE_OPTIONS.key?(minutes) },
        "task_kind" => attrs["task_kind"].to_s.presence_in(Task::KINDS.keys),
        "task_priority" => attrs["task_priority"].to_s.presence_in(Task::PRIORITIES.keys),
        "finish_message" => attrs["finish_message"].to_s.strip,
        "automation_workflow_id" => attrs["automation_workflow_id"].to_s.strip,
        "accept_timeout_minutes" => attrs["accept_timeout_minutes"].to_i.then { |minutes| minutes.clamp(1, 1440) if minutes.positive? },
        "inside_hours_message" => default_inside_hours_message(action, attrs["inside_hours_message"]),
        "outside_hours_message" => default_outside_hours_message(action, attrs["outside_hours_message"]),
        # Horário de atendimento só vale nas ações que o oferecem; nas demais um "ligado" antigo é ignorado.
        "business_hours" => normalize_business_hours(business_hours || {}).then { |hours| HOURS_ACTIONS.include?(action) ? hours : hours.merge("enabled" => "0") }
      }.compact_blank
    end
  end

  def default_message_for(action, value)
    text = value.to_s.strip
    return text if text.present?

    action == "send_message" ? DEFAULT_AUTO_REPLY_MESSAGE : nil
  end

  def default_inside_hours_message(action, value)
    text = value.to_s.strip
    return text if text.present?

    %w[send_message distribute_lead send_to_user].include?(action) ? DEFAULT_AUTO_REPLY_MESSAGE : nil
  end

  def default_outside_hours_message(action, value)
    text = value.to_s.strip
    return text if text.present?

    %w[send_message distribute_lead send_to_user].include?(action) ? DEFAULT_OUTSIDE_HOURS_MESSAGE : nil
  end

  def normalize_business_hours(hours)
    DEFAULT_BUSINESS_HOURS.merge(
      "enabled" => hours["enabled"].to_s,
      "days" => Array(hours["days"]).map(&:to_s) & DAY_KEYS,
      "start" => normalize_time(hours["start"], "08:00"),
      "end" => normalize_time(hours["end"], "18:00")
    )
  end

  def normalize_time(value, fallback)
    text = value.to_s.strip
    text.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/) ? text : fallback
  end

  def template_belongs_to_tenant
    return if whatsapp_template.blank? || tenant.blank? || whatsapp_template.tenant_id == tenant_id

    errors.add(:whatsapp_template, "deve pertencer à mesma conta")
  end

  def template_must_be_for_response_flow
    return if whatsapp_template.blank?
    return if %w[response_flow attendance].include?(whatsapp_template.usage_context.to_s)

    errors.add(:whatsapp_template, "deve estar classificado para fluxo de resposta ou atendimento")
  end

  def automation_workflow_belongs_to_tenant
    return if automation_workflow.blank? || tenant.blank? || automation_workflow.tenant_id == tenant_id

    errors.add(:automation_workflow, "deve pertencer à mesma conta")
  end

  def attendance_actions_must_have_target_agent
    return if tenant.blank?

    button_actions.to_h.each_value do |action|
      case action["action"].to_s
      when "run_automation"
        next if tenant.automation_workflows.where.not(status: "archived").exists?(id: action["automation_workflow_id"])

        errors.add(:base, "Escolha a automação do botão #{action['button_text']}")
      when "create_task"
        next if action["task_user_id"].blank? || tenant.admin_users.active.exists?(id: action["task_user_id"])

        errors.add(:base, "Selecione um usuário válido para a tarefa do botão #{action['button_text']}")
      when "send_to_user"
        next if tenant.admin_users.active.exists?(id: action["target_user_id"])

        errors.add(:base, "Selecione o usuário do botão #{action['button_text']}")
      when "distribute_lead"
        rule = tenant.distribution_rules.find_by(id: action["distribution_rule_id"])
        ids = Array(action["target_admin_user_ids"])
        next unless rule
        next if ids.any? && ids.all? { |id| rule.eligible_distribution_rule_agents.exists?(admin_user_id: id) }
        next if ids.empty? && !rule.attendance?

        errors.add(:base, ids.empty? ? "Selecione um atendente da regra #{rule.name} para o modo Atendimento" : "Selecione apenas atendentes elegíveis da regra #{rule.name}")
      end
    end
  end
end
