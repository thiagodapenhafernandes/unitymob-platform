# frozen_string_literal: true

module Security
  class LoginRateLimit
    EMAIL_PERIOD = 20.minutes.to_i
    IP_PERIOD = 5.minutes.to_i

    Result = Data.define(:email, :ips)

    def self.reset!(admin_user:, ip: nil)
      new(admin_user:, ip:).reset!
    end

    def initialize(admin_user:, ip: nil)
      @admin_user = admin_user
      @ip = ip.to_s.strip.presence
    end

    def reset!
      email = admin_user.email.to_s.downcase.strip
      ips = ([ip] + recent_denied_ips(email)).compact_blank.uniq

      Rack::Attack.cache.reset_count("admin/login/email:#{email}", EMAIL_PERIOD)
      ips.each { |candidate| Rack::Attack.cache.reset_count("admin/login/ip:#{candidate}", IP_PERIOD) }

      Result.new(email:, ips:)
    end

    private

    attr_reader :admin_user, :ip

    def recent_denied_ips(email)
      AccessAuditLog
        .where(event_type: "login", result: "denied", email: email)
        .where(created_at: 24.hours.ago..)
        .where.not(ip: nil)
        .distinct
        .pluck(:ip)
    end
  end
end
