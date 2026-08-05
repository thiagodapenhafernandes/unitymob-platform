module System
  class TenantProvisioner
    Result = Struct.new(:success?, :tenant, :owner, :form, keyword_init: true)

    def initialize(form:, actor:, request: nil)
      @form = form
      @actor = actor
      @request = request
    end

    def call
      return failure unless @form.valid?

      tenant = nil
      owner = nil

      ActiveRecord::Base.transaction do
        tenant = Tenant.create!(
          name: @form.tenant_name,
          slug: @form.tenant_slug,
          active: true
        )

        owner = create_owner!(tenant)
        create_primary_domain!(tenant)
      end

      audit!(tenant:, owner:)
      Result.new(success?: true, tenant:, owner:, form: @form)
    rescue ActiveRecord::RecordInvalid => e
      copy_record_errors(e.record)
      failure(tenant:, owner:)
    rescue ActiveRecord::RecordNotUnique
      @form.errors.add(:base, "Conta ou e-mail já cadastrado. Revise os dados e tente novamente.")
      failure(tenant:, owner:)
    end

    private

    def create_owner!(tenant)
      owner_profile = tenant.profiles.find_by!(key: "tenant_owner")

      tenant.admin_users.create!(
        name: @form.owner_name,
        email: @form.owner_email,
        phone: @form.owner_phone.presence,
        password: @form.owner_password,
        password_confirmation: @form.owner_password_confirmation,
        role: :admin,
        acting_type: :both,
        active: true,
        super_admin: false,
        profile: owner_profile
      )
    end

    def create_primary_domain!(tenant)
      return if @form.primary_domain_hostname.blank?

      tenant.tenant_domains.create!(
        hostname: @form.primary_domain_hostname,
        ssl_mode: @form.primary_domain_ssl_mode.presence || "not_configured",
        notes: @form.primary_domain_notes.presence,
        primary_domain: true,
        active: true
      )
    end

    def audit!(tenant:, owner:)
      AccessAuditLog.log!(
        event_type: "tenant_provisioned",
        result: "allowed",
        request: @request,
        admin_user: @actor,
        reason: "Conta criada pelo Admin do Sistema",
        metadata: {
          tenant_id: tenant.id,
          tenant_slug: tenant.slug,
          tenant_owner_id: owner.id
        }
      )
    end

    def copy_record_errors(record)
      record.errors.each do |error|
        @form.errors.add(:base, "#{record.class.model_name.human}: #{error.full_message}")
      end
    end

    def failure(tenant: nil, owner: nil)
      Result.new(success?: false, tenant:, owner:, form: @form)
    end
  end
end
