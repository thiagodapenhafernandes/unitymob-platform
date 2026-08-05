module Tenants
  class LocalPublicHostOverride
    HOST = "dev.unitymob.com.br".freeze

    class << self
      def available?
        Rails.env.development? || Rails.env.test?
      end

      def active_host?(host)
        available? && TenantDomain.normalize_host(host) == HOST
      end

      def tenant_for_host(host)
        return unless active_host?(host)

        tenant
      end

      def tenant
        return unless available?

        slug = path.read.strip if path.exist?
        Tenant.active.find_by(slug: slug) if slug.present?
      end

      def activate!(tenant)
        raise "Local public host override is unavailable in #{Rails.env}" unless available?

        FileUtils.mkdir_p(path.dirname)
        path.write(tenant.slug)
      end

      def clear!
        path.delete if path.exist?
      end

      def path
        Rails.root.join("tmp", "local_public_tenant_slug.#{Rails.env}")
      end
    end
  end
end
