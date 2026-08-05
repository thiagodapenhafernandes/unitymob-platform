module Tenants
  class DomainResolver
    attr_reader :matched_domain

    def initialize(host:, slug: nil)
      @host = host
      @slug = slug
    end

    def tenant
      @tenant ||= begin
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
