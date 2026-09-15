module Leads
  class InternalContactMatcher
    def self.call(tenant:, phone:)
      new(tenant:, phone:).call
    end

    def initialize(tenant:, phone:)
      @tenant = tenant
      @phone = Phones::Normalizer.call(phone).to_s.presence
    end

    def call
      return if tenant.blank? || phone.blank?

      tenant.admin_users
            .account_members
            .where("regexp_replace(coalesce(phone, ''), '\\D', '', 'g') = :phone OR regexp_replace(coalesce(secondary_phone, ''), '\\D', '', 'g') = :phone", phone: phone)
            .order(active: :desc, id: :asc)
            .first
    end

    private

    attr_reader :tenant, :phone
  end
end
