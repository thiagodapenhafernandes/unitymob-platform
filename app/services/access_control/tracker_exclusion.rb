module AccessControl
  module TrackerExclusion
    module_function

    def excluded?(request)
      ip = request&.remote_ip.to_s
      return false if ip.blank?

      tenant = Current.tenant
      return false if tenant.blank?

      AccessControlRule.matching_ip_for_tenant(ip, tenant).any? do |rule|
        rule.rule_type == "ignore_tracking_ip" || rule.rule_type == "block_ip"
      end
    end
  end
end
