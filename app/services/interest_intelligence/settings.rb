module InterestIntelligence
  class Settings
    DEFAULTS = {
      "price_tolerance_percent" => 15,
      "minimum_match_score" => 65,
      "strong_interest_views" => 2,
      "max_suggestions" => 5,
      "broker_review_required" => true,
      "requires_public_tracking_consent" => true,
      "allow_direct_lead_message" => false,
      "idle_without_match_hours" => 48,
      "city_weight" => 25,
      "neighborhood_weight" => 20,
      "category_weight" => 20,
      "bedrooms_weight" => 15,
      "parking_weight" => 5,
      "price_weight" => 20
    }.freeze

    def self.current
      new(LayoutSetting.instance)
    end

    def initialize(layout_setting)
      @layout_setting = layout_setting
    end

    def enabled?
      return true unless @layout_setting.respond_to?(:interest_intelligence_enabled)

      ActiveModel::Type::Boolean.new.cast(@layout_setting.interest_intelligence_enabled)
    end

    def [](key)
      settings.fetch(key.to_s, DEFAULTS[key.to_s])
    end

    def settings
      DEFAULTS.merge(@layout_setting.interest_intelligence_settings.to_h)
    end

    def instructions
      InterestIntelligence::SystemInstructions.effective_text(@layout_setting)
    end

    def enabled_value?(key)
      ActiveModel::Type::Boolean.new.cast(self[key])
    end
  end
end
