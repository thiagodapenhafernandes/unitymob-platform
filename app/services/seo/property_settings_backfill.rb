module Seo
  class PropertySettingsBackfill
    Result = Struct.new(:evaluated, :created, :updated, :skipped, :errors, keyword_init: true)

    def initialize(scope: nil, tenant: Current.tenant)
      raise ArgumentError, "Tenant obrigatório para backfill SEO" if tenant.blank?

      @tenant = tenant
      @scope = scope || tenant.habitations.active
      @result = Result.new(evaluated: 0, created: 0, updated: 0, skipped: 0, errors: 0)
    end

    def call
      @scope.find_each { |habitation| process(habitation) }
      @result
    end

    private

    def process(habitation)
      @result.evaluated += 1
      unless habitation.publicly_viewable?
        @result.skipped += 1
        return
      end

      attributes = Seo::PropertyMetadataBuilder.new(habitation).attributes
      seo = @tenant.seo_settings.find_or_initialize_by(canonical_key: attributes[:canonical_key])

      if seo.persisted? && seo.manual_mode?
        @result.skipped += 1
        return
      end

      created = seo.new_record?
      seo.page_name = attributes[:page_name] if seo.page_name.blank?
      seo.assign_attributes(
        attributes.except(:canonical_key, :page_name).merge(
          active: true,
          apply_to_public: true,
          auto_discovered: true,
          controller_name: "habitations",
          action_name: "show",
          robots_index: true,
          robots_follow: true
        )
      )
      seo.save!

      created ? @result.created += 1 : @result.updated += 1
    rescue StandardError => e
      @result.errors += 1
      Rails.logger.warn("[Seo::PropertySettingsBackfill] habitation=#{habitation.id} #{e.class}: #{e.message}")
    end
  end
end
