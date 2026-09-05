module Admin
  class AuditFilterOptions
    def initialize(tenant:, admin_user_ids:)
      @tenant = tenant
      @admin_user_ids = admin_user_ids
    end

    def users
      scope = @tenant.admin_users.account_members
      @admin_user_ids ? scope.where(id: @admin_user_ids) : scope
    end

    def profiles
      scope = users.reorder(nil)
      ids = scope.where(horizontal_profile_id: nil).where.not(profile_id: nil).distinct.pluck(:profile_id)
      ids += scope.where.not(horizontal_profile_id: nil).distinct.pluck(:horizontal_profile_id)
      @tenant.profiles.where(id: ids.compact.uniq).order(Arel.sql("axis DESC, name ASC"))
    end
  end
end
