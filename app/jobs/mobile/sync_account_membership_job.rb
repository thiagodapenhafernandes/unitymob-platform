module Mobile
  class SyncAccountMembershipJob < ApplicationJob
    queue_as :default
    self.log_arguments = false
    retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5
    def perform(user_id, deleted_payload = nil)
      user = AdminUser.find_by(id: user_id)
      if deleted_payload
        AccountMembershipRegistrar.publish!(deleted_payload)
      elsif user
        AccountMembershipRegistrar.sync!(user)
        user.mirror_users.find_each { |mirror| AccountMembershipRegistrar.sync!(mirror) } unless user.mirror?
      end
    end
  end
end
