module Automation
  # Avalia se um lead satisfaz as condições da regra.
  class ConditionMatcher
    def self.match?(rule, lead)
      match_conditions?(rule.conditions_hash, lead)
    end

    def self.match_conditions?(conditions, lead)
      new(conditions, lead).match?
    end

    def self.workflow_node?(node, lead)
      config = (node[:config] || {}).with_indifferent_access
      checks = []

      if config[:stage].present?
        return false unless lead
        checks << (Lead.status_value(lead.status) == Lead.status_value(config[:stage]))
      end

      if config[:source].present?
        return false unless lead
        checks << lead.origin.to_s.casecmp?(config[:source].to_s)
      end

      return true if checks.empty?

      config[:operator].to_s == "or" ? checks.any? : checks.all?
    end

    def initialize(conditions, lead)
      @lead = lead
      @c = conditions.with_indifferent_access
    end

    def match?
      return false unless @lead
      stage_ok? && source_ok? && idle_ok?
    end

    private

    def stage_ok?
      want = @c[:stage].to_s
      return true if want.blank?
      Lead.status_value(@lead.status) == Lead.status_value(want)
    end

    def source_ok?
      want = @c[:source].to_s
      return true if want.blank?
      @lead.origin.to_s.casecmp?(want)
    end

    def idle_ok?
      hours = @c[:idle_hours].to_i
      return true if hours <= 0
      @lead.updated_at <= hours.hours.ago
    end
  end
end
