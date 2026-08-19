module Ai
  class PropertyShareCollectionCreator
    TooFewShareableRecords = Class.new(StandardError)
    Result = Struct.new(:collection, :habitations, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(tenant:, admin_user:, scope:, setting: nil, source: "property_search", min_count: 1, lead: nil, expires_at: nil, message: nil)
      @tenant = tenant
      @admin_user = admin_user
      @scope = scope
      @setting = setting || PropertySetting.instance(tenant:)
      @source = source
      @min_count = min_count
      @lead = lead
      @expires_at = expires_at
      @message = message
    end

    def call
      habitations = shareable_habitations
      raise ActiveRecord::RecordNotFound if habitations.empty?
      raise TooFewShareableRecords if habitations.size < min_count

      collection = tenant.ai_property_share_collections.create!(
        admin_user:,
        lead:,
        expires_at:,
        message: message.presence
      )

      AiPropertyShareItem.insert_all!(
        habitations.map do |habitation|
          {
            ai_property_share_collection_id: collection.id,
            habitation_id: habitation.id,
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      )

      collection.record!(
        "collection_created",
        admin_user:,
        metadata: {
          habitation_ids: habitations.map(&:id),
          requested_count: requested_count,
          lead_id: lead&.id,
          source:
        }
      )

      Result.new(collection:, habitations:)
    end

    private

    attr_reader :tenant, :admin_user, :scope, :setting, :source, :min_count, :lead, :expires_at, :message

    def shareable_habitations
      @shareable_habitations ||= tenant.habitations
        .merge(scope)
        .shareable_commercial_selection
        .order(:id)
        .limit(setting.ai_property_search_share_max_properties)
        .to_a
    end

    def requested_count
      @requested_count ||= scope.reorder(nil).count
    end
  end
end
