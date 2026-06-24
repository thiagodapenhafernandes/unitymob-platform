module Automation
  class WorkflowActionAdapter
    def self.to_action(node)
      new(node).to_action
    end

    def initialize(node)
      @node = node.with_indifferent_access
      @config = (@node[:config].is_a?(Hash) ? @node[:config] : {}).with_indifferent_access
    end

    def to_action
      type = @config[:action_type].to_s
      action = { "type" => type }

      case type
      when "create_task"
        action["title"] = @config[:title].presence || @config[:message].presence || @node[:label]
        action["due_in_hours"] = @config[:due_in_hours] if @config[:due_in_hours].present?
        action["fallback_admin_user_id"] = @config[:fallback_admin_user_id] if @config[:fallback_admin_user_id].present?
      when "send_whatsapp"
        action["message"] = @config[:message]
      when "send_whatsapp_template"
        action["template"] = @config[:template].presence || @config[:message]
      when "move_stage"
        action["to"] = @config[:to].presence || @config[:message]
      when "assign_agent"
        action["admin_user_id"] = @config[:admin_user_id].presence || @config[:message]
      when "add_note"
        action["body"] = @config[:body].presence || @config[:message]
      when "create_interest_curation_task"
        action["title"] = @config[:title].presence || @node[:label]
        action["due_in_hours"] = @config[:due_in_hours] if @config[:due_in_hours].present?
        action["fallback_admin_user_id"] = @config[:fallback_admin_user_id] if @config[:fallback_admin_user_id].present?
        action["notes"] = @config[:notes] if @config[:notes].present?
      when "add_interest_note"
        action["body"] = @config[:body].presence || @config[:message]
      when "suggest_matching_properties"
        action["limit"] = @config[:limit] if @config[:limit].present?
      when "notify_broker_interest_opportunity"
        action["title"] = @config[:title].presence || @node[:label]
        action["due_in_hours"] = @config[:due_in_hours] if @config[:due_in_hours].present?
        action["fallback_admin_user_id"] = @config[:fallback_admin_user_id] if @config[:fallback_admin_user_id].present?
      when "prepare_matching_properties_whatsapp"
        action["limit"] = @config[:limit] if @config[:limit].present?
        action["message_prefix"] = @config[:message_prefix] if @config[:message_prefix].present?
        action["fallback_admin_user_id"] = @config[:fallback_admin_user_id] if @config[:fallback_admin_user_id].present?
      when "generate_interest_ai_summary"
        action["include_lead_message"] = @config[:include_lead_message]
      end

      action.compact
    end
  end
end
