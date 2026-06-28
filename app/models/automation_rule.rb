class AutomationRule < ApplicationRecord
  # Gatilhos disponíveis (QUANDO)
  TRIGGERS = {
    "lead_created"       => "Quando um lead é criado",
    "lead_stage_changed" => "Quando o lead muda de etapa",
    "lead_assigned"      => "Quando o lead é atribuído",
    "lead_idle"          => "Quando o lead fica parado (sem ação)",
    "proposal_viewed"    => "Quando o cliente visualiza a proposta",
    "proposal_accepted"  => "Quando o cliente aceita a proposta",
    "proposal_rejected"  => "Quando o cliente recusa a proposta",
    "whatsapp_received"  => "Quando o lead responde no WhatsApp",
    "whatsapp_campaign_started" => "Quando um disparo WhatsApp inicia",
    "whatsapp_campaign_completed" => "Quando um disparo WhatsApp conclui",
    "whatsapp_campaign_failed" => "Quando um disparo WhatsApp falha",
    "whatsapp_campaign_message_sent" => "Quando mensagem de disparo é enviada",
    "whatsapp_campaign_message_delivered" => "Quando mensagem de disparo é entregue",
    "whatsapp_campaign_message_read" => "Quando mensagem de disparo é lida",
    "whatsapp_campaign_message_failed" => "Quando mensagem de disparo falha",
    "whatsapp_campaign_message_replied" => "Quando lead responde um disparo",
    "scheduled_routine"  => "Rotina agendada",
    "interest_profile_detected" => "Quando interesse em imóveis é detectado",
    "matching_property_found" => "Quando surgir imóvel compatível",
    "lead_without_matching_property" => "Quando não houver imóvel compatível",
    "interest_profile_incomplete" => "Quando o perfil de interesse estiver incompleto",
    "interested_property_price_dropped" => "Quando imóvel de interesse baixar preço",
    "lead_repeated_similar_property_views" => "Quando lead visitar imóveis parecidos"
  }.freeze

  # Tipos de ação (ENTÃO)
  ACTION_TYPES = {
    "create_task"             => "Criar tarefa",
    "send_whatsapp"           => "Enviar WhatsApp (texto)",
    "send_whatsapp_template"  => "Enviar modelo WhatsApp",
    "send_webhook"            => "Enviar webhook",
    "set_flow_result"         => "Definir resultado do caminho",
    "move_stage"              => "Mover para etapa",
    "update_lead_lifecycle"   => "Atualizar ciclo de vida",
    "assign_agent"            => "Ação vertical legada",
    "add_note"                => "Registrar nota",
    "create_interest_curation_task" => "Criar tarefa de curadoria",
    "add_interest_note"       => "Registrar interesse detectado",
    "suggest_matching_properties" => "Sugerir imóveis compatíveis",
    "notify_broker_interest_opportunity" => "Criar alerta para responsável do lead",
    "prepare_matching_properties_whatsapp" => "Preparar WhatsApp com imóveis sugeridos",
    "generate_interest_ai_summary" => "Gerar resumo inteligente",
    "wait"                    => "Esperar (nutrição)"
  }.freeze

  VERTICAL_DISTRIBUTION_ACTION_TYPES = %w[assign_agent].freeze
  INTERVENTION_ACTION_TYPES = ACTION_TYPES.except(*VERTICAL_DISTRIBUTION_ACTION_TYPES).freeze

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
    Automation::ActionExecutor.label(action)
  end
end
