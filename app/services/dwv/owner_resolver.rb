module Dwv
  class OwnerResolver
    USER_EMAIL = "laudicardoso@gmail.com".freeze
    USER_NAME = "Dwv - Imóveis Pauta".freeze

    def self.call(tenant)
      new(tenant).call
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def call
      return if tenant.blank?

      account_users.find_by(email: USER_EMAIL) ||
        account_users.where("LOWER(name) = ?", USER_NAME.downcase).first ||
        account_users.where("LOWER(name) LIKE ?", "dwv%").order(:id).first
    end

    private

    attr_reader :tenant

    def account_users
      @account_users ||= tenant.admin_users.account_members
    end
  end
end
