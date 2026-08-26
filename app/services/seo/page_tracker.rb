module Seo
  class PageTracker
    AUTO_INVENTORY_SETTING = "seo_auto_inventory_enabled".freeze
    AUTO_APPLY_SETTING = "seo_auto_apply_enabled".freeze
    AUTO_AI_SETTING = "seo_ai_auto_generate_enabled".freeze

    def self.track!(controller)
      new(controller).track!
    end

    def self.enabled?(tenant: Current.tenant)
      Setting.tenant_get(AUTO_INVENTORY_SETTING, "1", tenant: tenant) == "1"
    end

    def self.auto_apply?(tenant: Current.tenant)
      Setting.tenant_get(AUTO_APPLY_SETTING, "1", tenant: tenant) == "1"
    end

    def self.auto_ai?(tenant: Current.tenant)
      Setting.tenant_get(AUTO_AI_SETTING, "1", tenant: tenant) == "1"
    end

    def initialize(controller)
      @controller = controller
    end

    def track!
      return unless trackable?

      identity = PageIdentity.new(@controller).to_h
      tenant = page_tenant
      seo = tenant.seo_settings.find_or_initialize_by(canonical_key: identity[:canonical_key])
      created = seo.new_record?

      unless created || !seo.manual_mode?
        record_page_visit(seo)
        return seo
      end

      seo.assign_attributes(attributes_for(identity, created))
      # Evita callbacks e invalidação do cache global do rodapé quando a
      # descoberta não alterou metadados. O acesso é registrado separadamente.
      seo.save! if created || seo.changed?
      record_page_visit(seo)

      enqueue_ai_generation(seo) if created && self.class.auto_ai?(tenant: tenant) && Ai::SeoContentService.connected?(tenant: tenant)
      seo
    rescue => e
      Rails.logger.warn("[Seo::PageTracker] #{e.class}: #{e.message}")
      nil
    end

    private

    def trackable?
      self.class.enabled?(tenant: page_tenant) &&
        @controller.request.get? &&
        @controller.request.format.html? &&
        !admin_request? &&
        !internal_path? &&
        !shared_link_request? &&
        !AccessControl::TrackerExclusion.excluded?(@controller.request)
    end

    def admin_request?
      @controller.request.path.start_with?("/admin")
    end

    def internal_path?
      path = @controller.request.path
      path.start_with?("/rails/", "/assets/", "/packs/", "/cable")
    end

    def shared_link_request?
      path = @controller.request.path.to_s
      query = @controller.request.query_parameters

      path.start_with?(SeoSetting::SHARED_LINK_PATH_PREFIX) ||
        query.key?(SeoSetting::SHARE_TOKEN_PARAM)
    end

    def attributes_for(identity, created)
      {
        page_name: identity[:page_name],
        page_type: identity[:page_type],
        controller_name: @controller.controller_name,
        action_name: @controller.action_name,
        canonical_path: identity[:canonical_path],
        canonical_url: "#{public_base_url}#{identity[:canonical_path]}",
        normalized_params: identity[:normalized_params],
        robots_index: identity[:robots_index],
        robots_follow: identity[:robots_follow],
        active: true,
        apply_to_public: created ? self.class.auto_apply?(tenant: page_tenant) : nil,
        auto_discovered: true,
        last_generated_from_path: @controller.request.fullpath,
        meta_title: existing_or_fallback(identity, :title_fallback, created),
        meta_description: existing_or_fallback(identity, :description_fallback, created),
        meta_keywords: existing_or_fallback(identity, :keywords_fallback, created),
        intro_text: existing_or_fallback(identity, :intro_fallback, created),
        og_title: existing_or_fallback(identity, :og_title_fallback, created) || existing_or_fallback(identity, :title_fallback, created),
        og_description: existing_or_fallback(identity, :og_description_fallback, created) || existing_or_fallback(identity, :description_fallback, created)
      }.compact
    end

    def existing_or_fallback(identity, key, created)
      return nil unless created || identity[:refresh_public_metadata]

      identity[key].to_s.presence
    end

    def enqueue_ai_generation(seo)
      SeoAiGenerationJob.perform_later(seo.id, tenant_id: seo.tenant_id)
    end

    def page_tenant
      @page_tenant ||= Current.tenant || @controller.public_tenant
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

    def public_base_url
      page_tenant.public_base_url(fallback_base_url: @controller.request.base_url)
    end
  end
end
