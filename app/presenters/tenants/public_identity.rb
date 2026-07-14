module Tenants
  class PublicIdentity
    attr_reader :tenant

    def initialize(tenant)
      @tenant = tenant || raise(ArgumentError, "Tenant obrigatório para identidade pública")
    end

    def name
      layout.site_name.presence || tenant.name
    end

    def email
      contact.email_primary.presence || footer.email.presence
    end

    def phone
      contact.phone.presence || contact.whatsapp_primary.presence || footer.whatsapp.presence
    end

    def address
      contact.address.presence
    end

    def social_urls
      [contact.instagram_url, contact.facebook_url, contact.youtube_url, contact.linkedin_url].compact_blank.uniq
    end

    def locations
      footer.footer_stores.filter_map do |store|
        next if store.address.blank?

        { name: store.name.presence || name, address: store.address, postal_code: store.zip_code }
      end.presence || [{ name: name, address: address, postal_code: nil }].select { |location| location[:address].present? }
    end

    def primary_city
      configured = PublicSiteProfile.current(tenant: tenant).primary_city.to_s.strip.presence
      return configured if configured

      tenant.habitations.left_outer_joins(:address)
        .where(exibir_no_site_flag: true)
        .where("NULLIF(TRIM(COALESCE(addresses.cidade, habitations.cidade)), '') IS NOT NULL")
        .group(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(1)
        .pick(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
        .presence
    end

    private

    def layout
      @layout ||= LayoutSetting.instance(tenant: tenant)
    end

    def contact
      @contact ||= ContactSetting.instance(tenant: tenant)
    end

    def footer
      @footer ||= FooterSetting.instance(tenant: tenant)
    end
  end
end
