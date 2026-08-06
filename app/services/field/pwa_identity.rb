module Field
  class PwaIdentity
    FALLBACK_BRAND = "Unitymob".freeze
    FALLBACK_THEME_COLOR = "#365F8F".freeze

    attr_reader :tenant, :layout

    def initialize(tenant)
      @tenant = tenant.presence || Tenant.public_for
      @layout = LayoutSetting.with_attached_logo.with_attached_favicon.find_by(tenant: @tenant) ||
        LayoutSetting.instance(tenant: @tenant)
    end

    def brand_name
      Tenants::PublicIdentity.new(tenant).name.presence ||
        layout.site_name.to_s.strip.presence ||
        tenant.name.to_s.strip.presence ||
        FALLBACK_BRAND
    end

    def full_name
      "#{brand_name} — Campo"
    end

    def short_name
      "#{brand_name} Campo".truncate(18, omission: "")
    end

    def apple_title
      "#{brand_name} Campo".truncate(30, omission: "")
    end

    def tenant_slug
      tenant.slug.to_s
    end

    def manifest_id
      "/field?tenant=#{tenant_slug}"
    end

    def start_url
      "/field?tenant=#{tenant_slug}"
    end

    def icon_version
      layout.updated_at.to_i
    end

    def icon_src(size)
      "/pwa-icon-#{size}?tenant=#{tenant_slug}&v=#{icon_version}"
    end

    def theme_color
      layout.admin_primary_color.presence || FALLBACK_THEME_COLOR
    end
  end
end
