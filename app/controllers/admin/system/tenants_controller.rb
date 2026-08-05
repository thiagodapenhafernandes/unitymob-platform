module Admin
  module System
    class TenantsController < Admin::BaseController
      before_action :require_system_admin!
      before_action :set_tenant, only: [:show, :edit, :update, :inactivate, :reactivate, :activate_dev_host]

      def index
        @query = params[:q].to_s.squish
        @status = params[:status].presence_in(%w[active inactive]) || "all"
        @tenants = filtered_tenants
        @tenant_owners_by_tenant_id = tenant_owners_by_tenant_id(@tenants)
        @account_user_counts_by_tenant_id = account_user_counts_by_tenant_id(@tenants)
        @local_public_tenant = Tenants::LocalPublicHostOverride.tenant if Tenants::LocalPublicHostOverride.available?
      end

      def show
        @owner = tenant_owner_for(@tenant)
        @profile_count = @tenant.profiles.count
        @account_users_count = @tenant.admin_users.account_members.count
        @account_users = @tenant.admin_users.account_members.includes(:profile, :horizontal_profile).order(active: :desc, name: :asc).limit(12)
        @tenant_domains = @tenant.tenant_domains.primary_first
      end

      def new
        @tenant_form = TenantProvisioningForm.new
      end

      def create
        @tenant_form = TenantProvisioningForm.new(tenant_form_params)
        result = ::System::TenantProvisioner.new(
          form: @tenant_form,
          actor: current_admin_user,
          request: request
        ).call

        if result.success?
          redirect_to admin_system_tenant_path(result.tenant),
                      notice: "Conta #{result.tenant.name} criada com #{result.owner.name} como Dono da conta."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @tenant_domains = @tenant.tenant_domains.primary_first
        @tenant_domain = @tenant.tenant_domains.new(active: true, ssl_mode: "not_configured")
      end

      def update
        if protected_default_tenant? && tenant_params[:active].to_s == "0"
          @tenant.errors.add(:active, "não pode ser desativada para a conta principal")
          @tenant_domains = @tenant.tenant_domains.primary_first
          @tenant_domain = @tenant.tenant_domains.new(active: true, ssl_mode: "not_configured")
          render :edit, status: :unprocessable_entity
          return
        end

        if @tenant.update(tenant_params)
          audit!("tenant_updated", "Conta atualizada pelo Admin do Sistema")
          redirect_to admin_system_tenant_path(@tenant), notice: "Conta #{@tenant.name} atualizada com sucesso."
        else
          @tenant_domains = @tenant.tenant_domains.primary_first
          @tenant_domain = @tenant.tenant_domains.new(active: true, ssl_mode: "not_configured")
          render :edit, status: :unprocessable_entity
        end
      end

      def inactivate
        if protected_default_tenant?
          redirect_to admin_system_tenant_path(@tenant), alert: "A conta principal não pode ser inativada."
          return
        end

        @tenant.update!(active: false)
        audit!("tenant_inactivated", "Conta inativada pelo Admin do Sistema")
        redirect_to admin_system_tenant_path(@tenant), notice: "Conta #{@tenant.name} inativada."
      end

      def reactivate
        @tenant.update!(active: true)
        audit!("tenant_reactivated", "Conta reativada pelo Admin do Sistema")
        redirect_to admin_system_tenant_path(@tenant), notice: "Conta #{@tenant.name} reativada."
      end

      def activate_dev_host
        unless Tenants::LocalPublicHostOverride.available?
          redirect_to admin_system_tenants_path, alert: "Ativação local disponível apenas em desenvolvimento."
          return
        end

        Tenants::LocalPublicHostOverride.activate!(@tenant)
        audit!("tenant_dev_host_activated", "Tenant ativado no host local #{Tenants::LocalPublicHostOverride::HOST}")
        redirect_to admin_system_tenants_path,
                    notice: "#{@tenant.name} será exibida em https://#{Tenants::LocalPublicHostOverride::HOST}/ neste ambiente local."
      end

      private

      def filtered_tenants
        scope = Tenant.includes(admin_users: :profile).order(active: :desc, name: :asc)

        if @query.present?
          pattern = "%#{@query}%"
          scope = scope.where("tenants.name ILIKE :q OR tenants.slug ILIKE :q", q: pattern)
        end

        case @status
        when "active" then scope = scope.where(active: true)
        when "inactive" then scope = scope.where(active: false)
        end

        scope.paginate(page: params[:page], per_page: 30)
      end

      def set_tenant
        @tenant = Tenant.find(params[:id])
      end

      def tenant_params
        params.require(:tenant).permit(:name, :slug, :active)
      end

      def tenant_form_params
        params.fetch(:tenant_provisioning_form, {}).permit(
          :tenant_name,
          :tenant_slug,
          :primary_domain_hostname,
          :primary_domain_ssl_mode,
          :primary_domain_notes,
          :owner_name,
          :owner_email,
          :owner_phone,
          :owner_password,
          :owner_password_confirmation
        )
      end

      def tenant_owner_for(tenant)
        tenant.admin_users
          .account_members
          .active
          .joins(:profile)
          .where(profiles: { key: "tenant_owner", axis: Profile::AXES[:vertical] })
          .order(:name)
          .first
      end

      def tenant_owners_by_tenant_id(tenants)
        tenants.each_with_object({}) do |tenant, owners|
          owner = tenant.admin_users.find do |user|
            user.active? && !user.super_admin? && user.profile&.tenant_owner?
          end
          owners[tenant.id] = owner if owner
        end
      end

      def account_user_counts_by_tenant_id(tenants)
        tenant_ids = tenants.map(&:id)
        return {} if tenant_ids.blank?

        AdminUser.account_members.where(tenant_id: tenant_ids).group(:tenant_id).count
      end

      def protected_default_tenant?
        @tenant.slug == Tenant::DEFAULT_SLUG
      end

      def audit!(event_type, reason)
        AccessAuditLog.log!(
          event_type: event_type,
          result: "allowed",
          request: request,
          admin_user: current_admin_user,
          reason: reason,
          metadata: { tenant_id: @tenant.id, tenant_slug: @tenant.slug }
        )
      end
    end
  end
end
