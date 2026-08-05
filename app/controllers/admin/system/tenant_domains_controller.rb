module Admin
  module System
    class TenantDomainsController < Admin::BaseController
      before_action :require_system_admin!
      before_action :set_tenant
      before_action :set_domain, only: [:update, :destroy, :set_primary]

      def create
        @domain = @tenant.tenant_domains.new(domain_params)

        if @domain.save
          audit!("tenant_domain_created", @domain)
          redirect_to edit_admin_system_tenant_path(@tenant), notice: "Domínio #{@domain.hostname} adicionado."
        else
          redirect_to edit_admin_system_tenant_path(@tenant), alert: @domain.errors.full_messages.to_sentence
        end
      end

      def update
        if @domain.update(domain_params)
          audit!("tenant_domain_updated", @domain)
          redirect_to edit_admin_system_tenant_path(@tenant), notice: "Domínio #{@domain.hostname} atualizado."
        else
          redirect_to edit_admin_system_tenant_path(@tenant), alert: @domain.errors.full_messages.to_sentence
        end
      end

      def destroy
        hostname = @domain.hostname
        @domain.destroy!
        audit!("tenant_domain_destroyed", @domain, hostname:)
        redirect_to edit_admin_system_tenant_path(@tenant), notice: "Domínio #{hostname} removido."
      end

      def set_primary
        @domain.update!(primary_domain: true, active: true)
        audit!("tenant_domain_primary_set", @domain)
        redirect_to edit_admin_system_tenant_path(@tenant), notice: "Domínio #{@domain.hostname} definido como principal."
      end

      private

      def set_tenant
        @tenant = Tenant.find(params[:tenant_id])
      end

      def set_domain
        @domain = @tenant.tenant_domains.find(params[:id])
      end

      def domain_params
        params.require(:tenant_domain).permit(:hostname, :primary_domain, :active, :ssl_mode, :notes)
      end

      def audit!(event_type, domain, hostname: domain.hostname)
        AccessAuditLog.log!(
          event_type:,
          result: "allowed",
          request: request,
          admin_user: current_admin_user,
          reason: "Domínio da conta alterado pelo Admin do Sistema",
          metadata: {
            tenant_id: @tenant.id,
            tenant_slug: @tenant.slug,
            tenant_domain_id: domain.id,
            hostname:
          }
        )
      end
    end
  end
end
