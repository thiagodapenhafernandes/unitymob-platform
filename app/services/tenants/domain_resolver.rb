module Tenants
  class DomainResolver
    attr_reader :matched_domain

    def initialize(host:, slug: nil, local_preview_slug: nil)
      @host = host
      @slug = slug
      @local_preview_slug = local_preview_slug
    end

    def tenant
      @tenant ||= begin
        if LocalPublicHostOverride.active_host?(@host) && @local_preview_slug.present?
          return Tenant.active.find_by!(slug: @local_preview_slug)
        end
        local_tenant = LocalPublicHostOverride.tenant_for_host(@host)
        if local_tenant
          local_tenant
        else
          @matched_domain = TenantDomain.find_for_host(@host)
          @matched_domain&.tenant || Tenant.public_for(slug: @slug)
        end
      end
    end
  end
end
