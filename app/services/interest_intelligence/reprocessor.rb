module InterestIntelligence
  class Reprocessor
    Result = Struct.new(
      :profile,
      :matches,
      :created_interests_count,
      :profile_event,
      :outcome_event,
      :profile_incomplete,
      keyword_init: true
    )

    def self.call(lead:, actor: nil, dispatch: true, idempotency_scope: nil)
      new(lead: lead, actor: actor, dispatch: dispatch, idempotency_scope: idempotency_scope).call
    end

    def initialize(lead:, actor:, dispatch:, idempotency_scope:)
      @lead = lead
      @actor = actor
      @dispatch = dispatch
      @idempotency_scope = idempotency_scope.to_s.presence
    end

    def call
      return disabled_result unless @lead && settings.enabled?

      created_count = create_interests_from_navigation
      matcher = InterestIntelligence::Matcher.new(@lead)
      profile = matcher.profile
      matches = matcher.call

      profile_event = emit_profile_event(profile)
      outcome_event = emit_outcome_event(profile, matches, matcher.profile_incomplete?)
      repeated_event = emit_repeated_interest_event(profile)
      record_timeline(profile, matches, created_count)

      Result.new(
        profile: profile,
        matches: matches,
        created_interests_count: created_count,
        profile_event: profile_event,
        outcome_event: outcome_event || repeated_event,
        profile_incomplete: matcher.profile_incomplete?
      )
    end

    private

    def disabled_result
      Result.new(
        profile: {},
        matches: [],
        created_interests_count: 0,
        profile_incomplete: true
      )
    end

    def create_interests_from_navigation
      created_count = 0

      @lead.public_navigation_events.property_signals.where.not(habitation_id: nil).find_each do |event|
        interest = ClientPropertyInterest.find_or_initialize_by(
          source_table: "public_navigation_events",
          source_key: event.id.to_s
        )

        created_count += 1 if interest.new_record?
        interest.assign_attributes(
          lead_id: @lead.id,
          habitation_id: event.habitation_id,
          interest_type: event.name,
          status: "observado",
          selected: @lead.property_id.to_i == event.habitation_id.to_i,
          started_at: interest.started_at || event.occurred_at,
          last_search_at: event.occurred_at,
          criteria: event.search_params.to_h,
          metadata: interest.metadata.to_h.merge(
            "source" => "public_site_navigation",
            "path" => event.path,
            "property_snapshot" => event.property_snapshot
          )
        )
        interest[:lead] = true
        interest.save!
      end

      created_count
    end

    def emit_profile_event(profile)
      Automation::Dispatcher.dispatch(
        :interest_profile_detected,
        @lead,
        source: "interest_intelligence",
        payload: event_payload(profile: profile),
        idempotency_key: idempotency_key(:interest_profile_detected),
        async: @dispatch
      )
    end

    def emit_outcome_event(profile, matches, profile_incomplete)
      if profile_incomplete
        Automation::Dispatcher.dispatch(
          :interest_profile_incomplete,
          @lead,
          source: "interest_intelligence",
          payload: event_payload(profile: profile),
          idempotency_key: idempotency_key(:interest_profile_incomplete),
          async: @dispatch
        )
      elsif matches.any?
        Automation::Dispatcher.dispatch(
          :matching_property_found,
          @lead,
          source: "interest_intelligence",
          payload: event_payload(
            profile: profile,
            matches: matches.map { |result| match_payload(result) }
          ),
          idempotency_key: idempotency_key(:matching_property_found, matches: matches),
          async: @dispatch
        )
      else
        Automation::Dispatcher.dispatch(
          :lead_without_matching_property,
          @lead,
          source: "interest_intelligence",
          payload: event_payload(profile: profile),
          idempotency_key: idempotency_key(:lead_without_matching_property),
          async: @dispatch
        )
      end
    end

    def emit_repeated_interest_event(profile)
      signals = profile.with_indifferent_access[:signals] || {}
      return if signals[:property_views].to_i < settings["strong_interest_views"].to_i

      Automation::Dispatcher.dispatch(
        :lead_repeated_similar_property_views,
        @lead,
        source: "interest_intelligence",
        payload: event_payload(profile: profile),
        idempotency_key: idempotency_key(:lead_repeated_similar_property_views),
        async: @dispatch
      )
    end

    def event_payload(profile:, matches: nil)
      {
        profile: profile,
        matches: matches,
        actor_id: @actor&.id,
        actor_name: @actor&.name,
        reprocessed_at: Time.current.iso8601
      }.compact
    end

    def record_timeline(profile, matches, created_count)
      return unless @actor

      LeadActivity.log!(
        lead: @lead,
        kind: "interest_reprocessed",
        metadata: {
          by: @actor&.name,
          confidence: profile.with_indifferent_access.dig(:confidence),
          matches_count: matches.size,
          created_interests_count: created_count
        }.compact
      )
    end

    def match_payload(result)
      {
        habitation_id: result.habitation.id,
        codigo: result.habitation.codigo,
        title: result.habitation.display_title,
        score: result.score,
        reasons: result.reasons
      }
    end

    def idempotency_key(event_name, matches: nil)
      return nil unless @idempotency_scope

      key = "#{event_name}:#{@idempotency_scope}:lead:#{@lead.id}"
      return key unless matches

      "#{key}:#{matches.map { |result| result.habitation.id }.join('-')}"
    end

    def settings
      @settings ||= InterestIntelligence::Settings.current
    end
  end
end
