module Automation
  class WhatsappCampaignWorkflowSync
    def self.call(campaign)
      new(campaign).call
    end

    def initialize(campaign)
      @campaign = campaign
    end

    def call
      return unless campaign&.persisted?
      return if decision_rows.blank?

      workflow = campaign.automation_workflow || campaign.tenant.automation_workflows.new(created_by: campaign.created_by)
      return workflow if workflow.persisted? && !workflow.whatsapp_campaign_managed?

      workflow.name = workflow_name
      workflow.status = "draft" if workflow.new_record?
      workflow.save!

      version = workflow.draft_version!
      version.update!(
        definition: definition,
        created_by: version.created_by || campaign.created_by
      )
      workflow.publish!(version: version, admin_user: campaign.created_by)
      campaign.update_column(:automation_workflow_id, workflow.id) if campaign.automation_workflow_id != workflow.id
      workflow
    end

    private

    attr_reader :campaign

    def decision_rows
      @decision_rows ||= campaign.response_decision_rows.select { |row| row["text"].present? }
    end

    def workflow_name
      "Disparo WhatsApp: #{campaign.name}".truncate(120)
    end

    def definition
      nodes = [entry_node]
      edges = []

      decision_rows.each_with_index do |row, index|
        condition_id = "button_#{index + 1}_condition"
        action_id = "button_#{index + 1}_action"
        nodes << condition_node(condition_id, row)
        nodes << action_node(action_id, row)
        edges << { "from" => "entry_campaign_reply", "to" => condition_id }
        edges << { "from" => condition_id, "to" => action_id }
      end

      {
        "schema_version" => 1,
        "source" => {
          "kind" => "whatsapp_campaign",
          "whatsapp_campaign_id" => campaign.id,
          "whatsapp_template_id" => campaign.whatsapp_template_id,
          "managed_by_campaign" => true,
          "customized_by_advanced_user" => false,
          "sync_mode" => "campaign_managed",
          "last_synced_at" => Time.current.iso8601
        },
        "nodes" => nodes,
        "edges" => edges,
        "viewport" => { "x" => 0, "y" => 0, "zoom" => 1 }
      }
    end

    def entry_node
      {
        "id" => "entry_campaign_reply",
        "type" => "entry",
        "label" => "Resposta do disparo",
        "config" => {
          "trigger" => "whatsapp_campaign_message_replied",
          "entry_policy" => "future",
          "whatsapp_campaign_id" => campaign.id,
          "whatsapp_template_id" => campaign.whatsapp_template_id
        }
      }
    end

    def condition_node(id, row)
      {
        "id" => id,
        "type" => "response_condition",
        "label" => "Botao: #{row['text']}",
        "config" => {
          "field" => "interaction.button_payload",
          "operator" => "equals",
          "value" => row["key"].presence || row["text"].to_s,
          "button_key" => row["key"].to_s,
          "button_payload" => row["key"].to_s,
          "button_text" => row["text"].to_s,
          "match_strategy" => "button_payload_or_text"
        }
      }
    end

    def action_node(id, row)
      {
        "id" => id,
        "type" => "action",
        "label" => row["action_label"].presence || WhatsappCampaign::RESPONSE_ACTIONS.fetch(row["action"].to_s, "Registrar resposta"),
        "config" => action_config(row)
      }
    end

    def action_config(row)
      case row["action"].to_s
      when "generate_lead"
        {
          "action_type" => "set_flow_result",
          "result" => "generates_attendance",
          "distribution_rule_id" => row["distribution_rule_id"].to_s,
          "note" => "Conversao gerada pelo botao #{row['text']} da campanha #{campaign.name}."
        }
      when "mark_no_interest"
        {
          "action_type" => "set_flow_result",
          "result" => "no_attendance",
          "note" => "Contato marcou sem interesse pelo botao #{row['text']}."
        }
      when "unsubscribe"
        {
          "action_type" => "update_lead_lifecycle",
          "lifecycle_action" => "unsubscribe_lead",
          "note" => "Contato solicitou descadastro pelo botao #{row['text']}."
        }
      when "send_message"
        {
          "action_type" => "send_whatsapp",
          "message" => row["message"].presence || "Obrigado pelo retorno. Nossa equipe vai acompanhar sua resposta."
        }
      when "create_task"
        {
          "action_type" => "create_task",
          "title" => "Acompanhar resposta: #{row['text']}",
          "due_in_hours" => 2
        }
      else
        {
          "action_type" => "set_flow_result",
          "result" => "record_only",
          "note" => "Resposta registrada pelo botao #{row['text']}."
        }
      end
    end
  end
end
