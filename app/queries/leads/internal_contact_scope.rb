module Leads
  class InternalContactScope
    MATCH_SQL = "regexp_replace(coalesce(leads.phone, ''), '\\D', '', 'g') IN (:phones) OR regexp_replace(coalesce(leads.client_phone, ''), '\\D', '', 'g') IN (:phones)".freeze

    def initialize(tenant:)
      @tenant = tenant
      raise ArgumentError, "tenant obrigatório" unless tenant&.persisted?
    end

    def matching
      return @tenant.leads.none if phones.empty?

      @tenant.leads.where(MATCH_SQL, phones: phones)
    end

    def exclude(scope)
      scope = scope.where(tenant_id: @tenant.id)
      return scope if phones.empty?

      scope.where.not(MATCH_SQL, phones: phones)
    end

    private

    def phones
      @phones ||= @tenant.admin_users.account_members.pluck(:phone, :secondary_phone)
        .flatten.filter_map { |phone| Phones::Normalizer.call(phone).to_s.presence }.uniq
    end
  end
end
