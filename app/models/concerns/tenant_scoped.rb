module TenantScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :tenant, optional: true
    validates :tenant, presence: true, unless: :tenant_optional?
    before_validation :assign_tenant_from_context

    scope :for_tenant, ->(tenant) { where(tenant: tenant) }
  end

  def tenant_optional?
    false
  end

  private

  def assign_tenant_from_context
    return if tenant_optional?

    self.tenant ||= inferred_tenant || Current.tenant
  end

  def inferred_tenant
    %i[
      admin_user
      profile
      created_by
      assigned_admin_user
      reenabled_by
      lead
      habitation
      whatsapp_campaign
      whatsapp_conversation
      whatsapp_business_integration
      whatsapp_template
      whatsapp_sender_number
      notification_template_setting
      distribution_rule
      store
      store_shift
      check_in
      manual_checkin_request
    ].each do |association_name|
      next unless respond_to?(association_name)

      associated = public_send(association_name)
      return associated.tenant if associated.respond_to?(:tenant) && associated.tenant.present?
    end

    nil
  end
end
