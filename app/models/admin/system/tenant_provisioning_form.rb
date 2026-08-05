module Admin
  module System
    class TenantProvisioningForm
      include ActiveModel::Model

      attr_accessor :tenant_name, :tenant_slug, :primary_domain_hostname, :primary_domain_ssl_mode,
                    :primary_domain_notes, :owner_name, :owner_email, :owner_phone, :owner_password,
                    :owner_password_confirmation

      validates :tenant_name, presence: true
      validates :owner_name, presence: true
      validates :owner_email, presence: true
      validates :owner_password, presence: true, length: { minimum: 8 }, confirmation: true
      validates :owner_password_confirmation, presence: true
      validates :primary_domain_ssl_mode, inclusion: { in: TenantDomain::SSL_MODES.keys }, allow_blank: true
      validate :tenant_slug_available
      validate :primary_domain_available
      validate :owner_email_available

      def self.model_name
        ActiveModel::Name.new(self, nil, "TenantProvisioningForm")
      end

      def self.human_attribute_name(attribute, options = {})
        {
          tenant_name: "Nome da conta",
          tenant_slug: "Slug",
          primary_domain_hostname: "Domínio principal",
          primary_domain_ssl_mode: "Modo de SSL",
          primary_domain_notes: "Observações do domínio",
          owner_name: "Nome completo",
          owner_email: "E-mail de acesso",
          owner_phone: "Celular / WhatsApp",
          owner_password: "Senha inicial",
          owner_password_confirmation: "Confirmação da senha inicial"
        }.fetch(attribute.to_sym) { super }
      end

      def initialize(attributes = {})
        super
        normalize_attributes
      end

      def tenant_name=(value)
        @tenant_name = value.to_s.squish
      end

      def tenant_slug=(value)
        @tenant_slug = value.to_s.parameterize.presence
      end

      def primary_domain_hostname=(value)
        @primary_domain_hostname = TenantDomain.normalize_host(value)
      end

      def primary_domain_ssl_mode=(value)
        @primary_domain_ssl_mode = value.to_s.presence
      end

      def primary_domain_notes=(value)
        @primary_domain_notes = value.to_s.squish
      end

      def owner_name=(value)
        @owner_name = value.to_s.squish
      end

      def owner_email=(value)
        @owner_email = value.to_s.downcase.strip
      end

      def owner_phone=(value)
        @owner_phone = value.to_s.squish
      end

      def persisted?
        false
      end

      private

      def normalize_attributes
        self.tenant_slug = tenant_name if tenant_slug.blank? && tenant_name.present?
        self.owner_email = owner_email
        self.primary_domain_ssl_mode ||= "not_configured"
      end

      def tenant_slug_available
        return if tenant_slug.blank?

        errors.add(:tenant_slug, "já está em uso") if Tenant.exists?(slug: tenant_slug)
      end

      def primary_domain_available
        return if primary_domain_hostname.blank?

        domain = TenantDomain.new(hostname: primary_domain_hostname, ssl_mode: primary_domain_ssl_mode)
        domain.valid?
        domain.errors.each do |error|
          next unless error.attribute == :hostname || error.attribute == :ssl_mode

          errors.add(error.attribute == :hostname ? :primary_domain_hostname : :primary_domain_ssl_mode, error.message)
        end

        if TenantDomain.where("lower(hostname) = ?", primary_domain_hostname).exists?
          errors.add(:primary_domain_hostname, "já está em uso")
        end
      end

      def owner_email_available
        return if owner_email.blank?

        errors.add(:owner_email, "já está em uso") if AdminUser.where("lower(email) = ?", owner_email).exists?
      end
    end
  end
end
