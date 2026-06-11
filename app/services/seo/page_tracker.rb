module Seo
  class PageTracker
    AUTO_INVENTORY_SETTING = "seo_auto_inventory_enabled".freeze
    AUTO_APPLY_SETTING = "seo_auto_apply_enabled".freeze
    AUTO_AI_SETTING = "seo_ai_auto_generate_enabled".freeze

    def self.track!(controller)
      new(controller).track!
    end

    def self.enabled?
      Setting.get(AUTO_INVENTORY_SETTING, "1") == "1"
    end

    def self.auto_apply?
      Setting.get(AUTO_APPLY_SETTING, "1") == "1"
    end

    def self.auto_ai?
      Setting.get(AUTO_AI_SETTING, "1") == "1"
    end

    def initialize(controller)
      @controller = controller
    end

    def track!
      return unless trackable?

      identity = PageIdentity.new(@controller).to_h
      seo = SeoSetting.find_or_initialize_by(canonical_key: identity[:canonical_key])
      created = seo.new_record?

      unless created || !seo.manual_mode?
        record_page_visit(seo)
        return seo
      end

      seo.assign_attributes(attributes_for(identity, created))
      seo.save!
      record_page_visit(seo)

      enqueue_ai_generation(seo) if created && self.class.auto_ai? && Ai::SeoContentService.connected?
      seo
    rescue => e
      Rails.logger.warn("[Seo::PageTracker] #{e.class}: #{e.message}")
      nil
    end

    private

    def trackable?
      self.class.enabled? &&
        @controller.request.get? &&
        @controller.request.format.html? &&
        @controller.response.successful? &&
        !admin_request? &&
        !internal_path? &&
        !AccessControl::TrackerExclusion.excluded?(@controller.request)
    end

    def admin_request?
      @controller.request.path.start_with?("/admin")
    end

    def internal_path?
      path = @controller.request.path
      path.start_with?("/rails/", "/assets/", "/packs/", "/cable")
    end

    def attributes_for(identity, created)
      {
        page_name: identity[:page_name],
        page_type: identity[:page_type],
        controller_name: @controller.controller_name,
        action_name: @controller.action_name,
        canonical_path: identity[:canonical_path],
        canonical_url: "#{@controller.request.base_url}#{identity[:canonical_path]}",
        normalized_params: identity[:normalized_params],
        robots_index: identity[:robots_index],
        robots_follow: identity[:robots_follow],
        active: true,
        apply_to_public: created ? self.class.auto_apply? : nil,
        auto_discovered: true,
        last_generated_from_path: @controller.request.fullpath,
        meta_title: existing_or_fallback(identity, :title_fallback, created),
        meta_description: existing_or_fallback(identity, :description_fallback, created),
        meta_keywords: existing_or_fallback(identity, :keywords_fallback, created),
        intro_text: existing_or_fallback(identity, :intro_fallback, created),
        og_title: existing_or_fallback(identity, :title_fallback, created),
        og_description: existing_or_fallback(identity, :description_fallback, created)
      }.compact
    end

    def existing_or_fallback(identity, key, created)
      return nil unless created

      identity[key].to_s.presence
    end

    def enqueue_ai_generation(seo)
      SeoAiGenerationJob.perform_later(seo.id)
    end

    def record_campaign_visit(seo)
      return if @controller.request.query_parameters["utm_campaign"].blank?

      event = Seo::ConversionTracker.record!(
        event_type: "campaign_click",
        request: @controller.request,
        metadata: {
          placement: "utm_landing",
          seo_setting_id: seo.id,
          page_url: @controller.request.fullpath
        }
      )
      event&.marketing_campaign&.register_click!
    rescue => e
      Rails.logger.warn("[Seo::PageTracker::CampaignVisit] #{e.class}: #{e.message}")
      nil
    end

    def record_page_visit(seo)
      return unless consent_accepted?

      seo.register_access!
      SeoPageVisit.record!(seo, @controller.request)
      record_campaign_visit(seo)
    end

    def consent_accepted?
      @controller.respond_to?(:lgpd_consent_accepted?) && @controller.lgpd_consent_accepted?
    end
  end
end
