module Automation
  # Avalia se um lead satisfaz as condições da regra.
  class ConditionMatcher
    def self.match?(rule, lead)
      new(rule, lead).match?
    end

    def initialize(rule, lead)
      @lead = lead
      @c = rule.conditions_hash
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
