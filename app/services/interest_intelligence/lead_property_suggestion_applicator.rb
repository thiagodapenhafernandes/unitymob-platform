module InterestIntelligence
  class LeadPropertySuggestionApplicator
    Result = Struct.new(:matches, :interests, :profile_incomplete, keyword_init: true) do
      def count
        interests.size
      end

      def empty?
        interests.empty?
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(lead:, tenant:, admin_user:, limit: nil)
      @lead = lead
      @tenant = tenant
      @admin_user = admin_user
      @settings = InterestIntelligence::Settings.current
      @limit = (limit.presence || @settings["max_suggestions"]).to_i.clamp(1, 10)
    end

    def call
      matcher = InterestIntelligence::Matcher.new(@lead, limit: matcher_limit)
      return Result.new(matches: [], interests: [], profile_incomplete: true) if matcher.profile_incomplete?

      matches = matcher.call.reject { |match| ignored_property_ids.include?(match.habitation.id) }.first(@limit)
      interests = LeadPropertyInterest.transaction do
        matches.map do |match|
          @lead.property_interests.find_or_create_by!(tenant: @tenant, habitation: match.habitation)
        end
      end

      log_suggestions(matches) if interests.any?
      Result.new(matches:, interests:, profile_incomplete: false)
    end

    private

    def matcher_limit
      [@limit * 5, 25].max
    end

    def ignored_property_ids
      @ignored_property_ids ||= begin
        ids = @lead.property_interests.pluck(:habitation_id)
        ids += @lead.client_property_interests.pluck(:habitation_id)
        ids += @lead.ai_property_share_collections.joins(:habitations).pluck("habitations.id")
        ids << @lead.property_id if @lead.respond_to?(:property_id) && @lead.property_id.present?
        ids.compact.uniq
      end
    end

    def log_suggestions(matches)
      LeadActivity.log!(
        lead: @lead,
        kind: "property_suggestions",
        metadata: {
          by: @admin_user&.name,
          habitation_ids: matches.map { |match| match.habitation.id },
          scores: matches.to_h { |match| [match.habitation.id, match.score] },
          reasons: matches.to_h { |match| [match.habitation.id, match.reasons] }
        }.compact
      )
    end
  end
end
