module Automation
  class WorkflowDefinition
    NODE_TYPES = %w[
      entry condition wait await_event await_whatsapp_response response_condition response_fallback
      response_router action branch exit
    ].freeze

    def self.default_definition
      {
        "schema_version" => 1,
        "nodes" => [
          {
            "id" => "entry_1",
            "type" => "entry",
            "label" => "Quando observar",
            "config" => {
              "trigger" => "lead_created",
              "entry_policy" => "future"
            }
          }
        ],
        "edges" => [],
        "viewport" => { "x" => 0, "y" => 0, "zoom" => 1 }
      }
    end

    def self.validate(definition, mode: :draft)
      new(definition).validate(mode: mode)
    end

    def initialize(definition)
      @definition = definition.is_a?(Hash) ? definition.with_indifferent_access : {}
    end

    def validate(mode: :draft)
      errors = []
      nodes = Array(@definition[:nodes]).map { |node| node.is_a?(Hash) ? node.with_indifferent_access : {} }
      edges = Array(@definition[:edges]).map { |edge| edge.is_a?(Hash) ? edge.with_indifferent_access : {} }

      errors << "precisa ter ao menos um bloco de entrada" if nodes.none? { |node| node[:type] == "entry" }
      errors << "precisa ter ao menos um bloco" if nodes.empty?

      node_ids = nodes.filter_map { |node| node[:id].presence }
      errors << "tem blocos sem identificador" if node_ids.size != nodes.size
      errors << "tem identificadores de bloco duplicados" if node_ids.uniq.size != node_ids.size

      nodes.each { |node| validate_node(node, errors) }
      edges.each { |edge| validate_edge(edge, node_ids, errors) }
      validate_publish_contract(nodes, edges, node_ids, errors) if mode.to_sym == :publish

      errors.uniq
    end

    private

    def validate_node(node, errors)
      type = node[:type].to_s
      config = node[:config].is_a?(Hash) ? node[:config].with_indifferent_access : {}

      errors << "tem bloco com tipo invalido" unless NODE_TYPES.include?(type)

      case type
      when "entry"
        errors << "tem entrada sem gatilho" unless AutomationRule::TRIGGERS.key?(config[:trigger].to_s)
        if config[:entry_policy].present? && !%w[future existing_and_future].include?(config[:entry_policy].to_s)
          errors << "tem entrada com politica invalida"
        end
      when "action"
        errors << "tem acao sem tipo" unless AutomationRule::ACTION_TYPES.key?(config[:action_type].to_s)
      when "wait"
        validate_wait_config(config, errors)
      when "await_event"
        errors << "tem espera por evento sem evento observado" unless Automation::EventCatalog.include?(config[:trigger])
        amount = config[:timeout_amount].presence || config[:amount]
        unit = config[:timeout_unit].presence || config[:unit]
        errors << "tem espera por evento sem timeout valido" unless amount.to_i.positive?
        errors << "tem espera por evento com unidade de timeout invalida" unless %w[minutes hours days].include?(unit.to_s)
      when "await_whatsapp_response"
        amount = config[:timeout_amount].presence || config[:amount]
        unit = config[:timeout_unit].presence || config[:unit]
        errors << "tem espera de resposta WhatsApp sem timeout valido" unless amount.to_i.positive?
        errors << "tem espera de resposta WhatsApp com unidade de timeout invalida" unless %w[minutes hours days].include?(unit.to_s)
      when "response_condition"
        errors << "tem condicao de resposta sem campo" if config[:field].blank?
        errors << "tem condicao de resposta com operador invalido" unless %w[equals contains not_contains present].include?(config[:operator].to_s.presence || "equals")
      when "response_fallback"
        errors << "tem fallback de resposta com tipo invalido" unless %w[timeout no_match].include?(config[:fallback_type].to_s.presence || "no_match")
      when "response_router"
        amount = config[:timeout_amount].presence || config[:amount]
        unit = config[:timeout_unit].presence || config[:unit]
        errors << "tem resposta condicional sem timeout valido" unless amount.to_i.positive?
        errors << "tem resposta condicional com unidade de timeout invalida" unless %w[minutes hours days].include?(unit.to_s)
      end
    end

    def validate_wait_config(config, errors)
      mode = config[:mode].presence || "duration"
      errors << "tem espera com modo invalido" unless %w[duration datetime business_duration next_business_window].include?(mode.to_s)

      if mode.to_s == "datetime"
        errors << "tem espera ate data/hora sem data definida" if config[:run_at].blank?
        return
      end

      return if mode.to_s == "next_business_window"

      amount = config[:amount].to_i
      unit = config[:unit].to_s
      errors << "tem espera sem duracao valida" unless amount.positive?
      errors << "tem espera com unidade invalida" unless %w[minutes hours days].include?(unit)
    end

    def validate_edge(edge, node_ids, errors)
      from = edge[:from].to_s
      to = edge[:to].to_s

      errors << "tem conexao sem origem" if from.blank?
      errors << "tem conexao sem destino" if to.blank?
      errors << "tem conexao apontando para bloco inexistente" if from.present? && !node_ids.include?(from)
      errors << "tem conexao apontando para destino inexistente" if to.present? && !node_ids.include?(to)
    end

    def validate_publish_contract(nodes, edges, node_ids, errors)
      entry_nodes = nodes.select { |node| node[:type].to_s == "entry" }
      errors << "precisa ter apenas um bloco de entrada" if entry_nodes.size > 1
      operational_nodes = nodes.reject { |node| %w[entry exit].include?(node[:type].to_s) }
      errors << "precisa ter ao menos uma etapa apos a entrada" if operational_nodes.empty?

      validate_required_configs(nodes, errors)
      validate_reachability(nodes, edges, errors)
      validate_branch_outputs(nodes, edges, errors)
      validate_duplicate_edges(edges, errors)
      validate_self_edges(edges, errors)
      validate_unknown_edge_nodes(edges, node_ids, errors)
    end

    def validate_required_configs(nodes, errors)
      nodes.each do |node|
        type = node[:type].to_s
        config = node[:config].is_a?(Hash) ? node[:config].with_indifferent_access : {}

        if type == "entry" && config[:trigger].to_s == "lead_idle" && config[:idle_hours].to_i <= 0
          errors << "tem entrada de lead parado sem horas validas"
        end
        if type == "entry" && config[:trigger].to_s == "scheduled_routine"
          frequency = config[:schedule_frequency].presence || "every_n_minutes"
          errors << "tem rotina agendada com frequencia invalida" unless %w[every_n_minutes daily weekly monthly].include?(frequency.to_s)
          errors << "tem rotina agendada sem intervalo valido" if frequency.to_s == "every_n_minutes" && config[:interval].to_i <= 0
          errors << "tem rotina agendada mensal sem dia valido" if frequency.to_s == "monthly" && config[:month_day].to_i <= 0
        end

        if type == "response_router"
          routes = Array(config[:routes])
          errors << "tem resposta condicional sem fluxo de resposta" if routes.empty?
          routes.each do |route|
            route_config = route.is_a?(Hash) ? route.with_indifferent_access : {}
            errors << "tem fluxo de resposta sem condicao" if Array(route_config[:conditions]).empty?
            errors << "tem fluxo de resposta sem acao" if Array(route_config[:actions]).empty?
            Array(route_config[:actions]).each do |action|
              action_config = action.is_a?(Hash) ? action.with_indifferent_access : {}
              action_type = action_config[:type].presence || action_config[:action_type]
              errors << "tem fluxo de resposta com acao invalida" unless %w[send_whatsapp add_note move_stage].include?(action_type.to_s)
              errors << "tem fluxo de resposta com WhatsApp sem mensagem" if action_type.to_s == "send_whatsapp" && action_config[:message].blank?
              errors << "tem fluxo de resposta com nota sem texto" if action_type.to_s == "add_note" && action_config[:body].blank?
              if action_type.to_s == "move_stage"
                errors << "tem fluxo de resposta com etapa sem destino" if action_config[:to].blank?
                if action_config[:to].present? && !Automation::StagePolicy.allowed_transition?(action_config[:to])
                  errors << Automation::StagePolicy.blocked_stage_message(action_config[:to])
                end
              end
            end
          end
        end

        next unless type == "action"

        case config[:action_type].to_s
        when *AutomationRule::VERTICAL_DISTRIBUTION_ACTION_TYPES
          errors << "tem acao vertical de distribuicao; use Distribuicao de Leads para definir responsavel, fila, aceite e represamento"
        when "create_task"
          errors << "tem acao de tarefa sem titulo" if config[:title].blank? && node[:label].blank?
        when "send_whatsapp"
          errors << "tem acao de WhatsApp sem mensagem" if config[:message].blank?
        when "send_whatsapp_template"
          errors << "tem acao de modelo WhatsApp sem template" if config[:template].blank?
        when "send_webhook"
          errors << "tem acao de webhook sem URL" if config[:url].blank?
          if config[:url].present? && config[:url] !~ URI::DEFAULT_PARSER.make_regexp(%w[http https])
            errors << "tem acao de webhook com URL invalida"
          end
          if config[:http_method].present? && !AutomationWebhookDelivery::HTTP_METHODS.include?(config[:http_method].to_s)
            errors << "tem acao de webhook com metodo invalido"
          end
        when "set_flow_result"
          result = config[:result].presence || "no_attendance"
          errors << "tem resultado de caminho invalido" unless %w[generates_attendance no_attendance record_only].include?(result.to_s)
          errors << "tem resultado que gera atendimento sem destino" if result.to_s == "generates_attendance" && config[:distribution_rule_id].blank?
        when "move_stage"
          errors << "tem acao de mover etapa sem destino" if config[:to].blank?
          if config[:to].present? && !Automation::StagePolicy.allowed_transition?(config[:to])
            errors << Automation::StagePolicy.blocked_stage_message(config[:to])
          end
        when "update_lead_lifecycle"
          errors << "tem acao de ciclo de vida sem tipo" unless %w[mark_no_interest remove_no_interest block_lead discard_lead unsubscribe_lead reactivate_lead].include?(config[:lifecycle_action].to_s)
          to = config[:to].presence
          if to.present? && !Automation::StagePolicy.allowed_transition?(to)
            errors << Automation::StagePolicy.blocked_stage_message(to)
          end
        when "assign_agent"
          errors << "tem acao de atribuir corretor sem responsavel" if config[:admin_user_id].blank?
        when "add_note"
          errors << "tem acao de nota sem texto" if config[:body].blank?
        when "create_interest_curation_task"
          errors << "tem acao de curadoria sem titulo" if config[:title].blank? && node[:label].blank?
        when "suggest_matching_properties"
          errors << "tem sugestao de imoveis com limite invalido" if config[:limit].present? && config[:limit].to_i <= 0
        when "prepare_matching_properties_whatsapp"
          errors << "tem WhatsApp de imoveis com limite invalido" if config[:limit].present? && config[:limit].to_i <= 0
        end

        if ActiveModel::Type::Boolean.new.cast(config[:retry_enabled])
          errors << "tem retentativa sem quantidade valida" if config[:retry_attempts].to_i <= 0
          errors << "tem retentativa sem intervalo valido" if config[:retry_delay_amount].to_i <= 0
          errors << "tem retentativa com unidade invalida" unless %w[minutes hours days].include?(config[:retry_delay_unit].to_s.presence || "minutes")
        end
      end
    end

    def validate_reachability(nodes, edges, errors)
      entry = nodes.find { |node| node[:type].to_s == "entry" }
      return unless entry

      reachable = [entry[:id].to_s]
      loop do
        next_ids = edges
          .select { |edge| reachable.include?(edge[:from].to_s) }
          .map { |edge| edge[:to].to_s }
          .reject(&:blank?)
        merged = (reachable + next_ids).uniq
        break if merged.size == reachable.size

        reachable = merged
      end

      unreachable = nodes.map { |node| node[:id].to_s } - reachable
      errors << "tem blocos desconectados da entrada" if unreachable.any?
    end

    def validate_branch_outputs(nodes, edges, errors)
      nodes.each do |node|
        type = node[:type].to_s
        outgoing = edges.count { |edge| edge[:from].to_s == node[:id].to_s }

        if %w[condition branch response_condition response_fallback].include?(type) && outgoing.zero?
          errors << "tem ramificacao sem caminho de saida"
        elsif %w[wait await_event await_whatsapp_response response_router].include?(type) && outgoing.zero?
          errors << "tem espera sem proxima etapa"
        elsif type == "entry" && outgoing.zero?
          errors << "tem entrada sem proxima etapa"
        end
      end
    end

    def validate_duplicate_edges(edges, errors)
      pairs = edges.map { |edge| [edge[:from].to_s, edge[:to].to_s] }
      errors << "tem conexoes duplicadas" if pairs.uniq.size != pairs.size
    end

    def validate_self_edges(edges, errors)
      errors << "tem conexao apontando para o mesmo bloco" if edges.any? { |edge| edge[:from].present? && edge[:from].to_s == edge[:to].to_s }
    end

    def validate_unknown_edge_nodes(edges, node_ids, errors)
      known = node_ids.map(&:to_s)
      return unless edges.any? { |edge| edge[:from].present? && !known.include?(edge[:from].to_s) } ||
                    edges.any? { |edge| edge[:to].present? && !known.include?(edge[:to].to_s) }

      errors << "tem conexoes para blocos desconhecidos"
    end
  end
end
