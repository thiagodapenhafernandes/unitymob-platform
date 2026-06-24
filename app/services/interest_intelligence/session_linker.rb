module InterestIntelligence
  class SessionLinker
    def self.call(lead:, token:)
      new(lead: lead, token: token).call
    end

    def initialize(lead:, token:)
      @lead = lead
      @token = token.to_s
    end

    def call
      return unless @lead && @token.present?

      session = PublicNavigationSession.find_by(token: @token)
      return unless session

      session.link_to_lead!(@lead)
      InterestIntelligence::Reprocessor.call(
        lead: @lead,
        idempotency_scope: "auto"
      )
    end
  end
end
