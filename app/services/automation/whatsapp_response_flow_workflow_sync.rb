module Automation
  class WhatsappResponseFlowWorkflowSync
    def self.call(flow)
      new(flow).call
    end

    def initialize(flow)
      @flow = flow
    end

    def call
      return unless flow&.persisted?
      return if decision_rows.blank?

      workflow = flow.automation_workflow || flow.tenant.automation_workflows.new(created_by: flow.created_by)
      return workflow if workflow.persisted? && !response_flow_managed?(workflow)

      workflow.name = flow.name.to_s.truncate(120)
      workflow.status = "draft" if workflow.new_record?
      workflow.save!

      version = workflow.draft_version!
      version.update!(
        definition: definition,
        created_by: version.created_by || flow.created_by
      )
      workflow.publish!(version: version, admin_user: flow.created_by)
      flow.update_column(:automation_workflow_id, workflow.id) if flow.automation_workflow_id != workflow.id
      workflow
    end

    private

    attr_reader :flow

    def decision_rows
      @decision_rows ||= flow.button_actions.to_h.values.select { |row| row["button_text"].present? }
    end

    def response_flow_managed?(workflow)
      [workflow.draft_version, workflow.active_version].compact.any? do |version|
        source = version.definition_hash.dig(:source).to_h.with_indifferent_access
        source[:kind].to_s == "whatsapp_response_flow" &&
          source[:whatsapp_response_flow_id].to_i == flow.id &&
          !ActiveModel::Type::Boolean.new.cast(source[:customized_by_advanced_user])
      end
    end

    def definition
      nodes = [entry_node]
      edges = []

      decision_rows.each_with_index do |row, index|
        condition_id = "button_#{index + 1}_condition"
        action_id = "button_#{index + 1}_action"
        nodes << condition_node(condition_id, row)
        nodes << action_node(action_id, row)
        edges << { "from" => "entry_whatsapp_response_flow", "to" => condition_id }
        edges << { "from" => condition_id, "to" => action_id }
      end

      {
        "schema_version" => 1,
        "source" => {
          "kind" => "whatsapp_response_flow",
          "whatsapp_response_flow_id" => flow.id,
          "whatsapp_template_id" => flow.whatsapp_template_id,
          "managed_by_response_flow" => true,
          "customized_by_advanced_user" => false,
          "sync_mode" => "response_flow_managed",
          "last_synced_at" => Time.current.iso8601
        },
        "nodes" => nodes,
        "edges" => edges,
        "viewport" => { "x" => 0, "y" => 0, "zoom" => 1 }
      }
    end

    def entry_node
      {
        "id" => "entry_whatsapp_response_flow",
        "type" => "entry",
        "label" => "Clique em botão WhatsApp",
        "config" => {
          "trigger" => "whatsapp_received",
          "entry_policy" => "future",
          "whatsapp_response_flow_id" => flow.id,
          "whatsapp_template_id" => flow.whatsapp_template_id
        }
      }
    end

    def condition_node(id, row)
      {
        "id" => id,
        "type" => "response_condition",
        "label" => "Botao: #{row['button_text']}",
        "config" => {
          "field" => "interaction.button_payload",
          "operator" => "equals",
          "value" => row["button_key"].presence || row["button_text"].to_s,
          "button_key" => row["button_key"].to_s,
          "button_payload" => row["button_key"].to_s,
          "button_text" => row["button_text"].to_s,
          "match_strategy" => "button_payload_or_text"
        }
      }
    end

    def action_node(id, row)
      action = row["action"].to_s
      {
        "id" => id,
        "type" => "action",
        "label" => WhatsappResponseFlow::ACTIONS.fetch(action, "Apenas registrar"),
        "config" => action_config(row)
      }
    end

    def action_config(row)
      case row["action"].to_s
      when "send_message"
        { "action_type" => "send_whatsapp", "message" => row["message"].presence || row["inside_hours_message"].presence || "Obrigado pelo retorno." }
      when "send_url"
        { "action_type" => "send_whatsapp", "message" => [row["message"].presence, row["url"].presence].compact.join("\n").presence || "Obrigado pelo retorno." }
      when "create_task"
        { "action_type" => "create_task", "title" => row["task_title"].presence || "Acompanhar resposta: #{row['button_text']}", "due_in_hours" => 2 }
      when "distribute_lead"
        {
          "action_type" => "set_flow_result",
          "result" => "generates_attendance",
          "distribution_rule_id" => row["distribution_rule_id"].to_s,
          "target_admin_user_id" => row["target_admin_user_id"].to_s,
          "target_admin_user_ids" => Array(row["target_admin_user_ids"]),
          "note" => "Atendimento gerado pelo botao #{row['button_text']} do fluxo #{flow.name}."
        }.compact_blank
      when "run_automation"
        { "action_type" => "set_flow_result", "result" => "record_only", "note" => "Botao #{row['button_text']} inicia uma automacao propria." }
      when "send_to_user"
        {
          "action_type" => "set_flow_result",
          "result" => "record_only",
          "target_user_id" => row["target_user_id"].to_s,
          "note" => "Resposta do botao #{row['button_text']} encaminhada a um usuario."
        }
      else
        {
          "action_type" => "set_flow_result",
          "result" => "record_only",
          "note" => "Resposta registrada pelo botao #{row['button_text']}."
        }
      end
    end
  end
end
