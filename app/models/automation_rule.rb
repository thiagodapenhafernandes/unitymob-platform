class AutomationRule < ApplicationRecord
  # Gatilhos disponíveis (QUANDO)
  TRIGGERS = {
    "lead_created"       => "Quando um lead é criado",
    "lead_stage_changed" => "Quando o lead muda de etapa",
    "lead_idle"          => "Quando o lead fica parado (sem ação)",
    "proposal_viewed"    => "Quando o cliente visualiza a proposta"
  }.freeze

  # Tipos de ação (ENTÃO)
  ACTION_TYPES = {
    "create_task"             => "Criar tarefa",
    "send_whatsapp"           => "Enviar WhatsApp (texto)",
    "send_whatsapp_template"  => "Enviar modelo WhatsApp",
    "move_stage"              => "Mover para etapa",
    "assign_agent"            => "Atribuir corretor",
    "add_note"                => "Registrar nota",
    "wait"                    => "Esperar (nutrição)"
  }.freeze

  TIME_BASED_TRIGGERS = %w[lead_idle].freeze

  has_many :automation_runs, dependent: :destroy

  validates :name, presence: true
  validates :trigger_event, inclusion: { in: TRIGGERS.keys }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :for_event, ->(event) { active.where(trigger_event: event.to_s) }
  scope :time_based, -> { active.where(trigger_event: TIME_BASED_TRIGGERS) }

  def trigger_label = TRIGGERS[trigger_event] || trigger_event

  def action_list
    Array(actions).map { |a| a.is_a?(Hash) ? a.with_indifferent_access : {} }
  end

  def conditions_hash
    (conditions.is_a?(Hash) ? conditions : {}).with_indifferent_access
  end

  def idle_hours
    conditions_hash[:idle_hours].to_i
  end

  def register_run!
    increment!(:runs_count)
    update_column(:last_run_at, Time.current)
  end

  # Resumo textual das ações para exibir no card ("ENTÃO ...")
  def actions_summary
    action_list.map { |a| action_label(a) }
  end

  def action_label(action)
    case action[:type]
    when "create_task"            then "criar tarefa “#{action[:title]}”"
    when "send_whatsapp"          then "enviar WhatsApp"
    when "send_whatsapp_template" then "enviar modelo “#{action[:template]}”"
    when "move_stage"             then "mover para “#{action[:to]}”"
    when "assign_agent"           then "atribuir corretor"
    when "add_note"               then "registrar nota"
    when "wait"                   then "esperar #{action[:days]} dia(s)"
    else action[:type].to_s
    end
  end
end
