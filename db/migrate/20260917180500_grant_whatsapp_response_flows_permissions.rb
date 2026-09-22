class GrantWhatsappResponseFlowsPermissions < ActiveRecord::Migration[7.1]
  class AccessProfile < ApplicationRecord
    self.table_name = "profiles"
  end

  def up
    AccessProfile.find_each do |profile|
      permissions = (profile.permissions || {}).deep_dup
      next unless permissions.dig("whatsapp_campaigns", "view") || permissions.dig("whatsapp_campaigns", "manage")

      permissions["whatsapp_response_flows"] ||= {}
      permissions["whatsapp_response_flows"]["view"] = true if permissions.dig("whatsapp_campaigns", "view")
      permissions["whatsapp_response_flows"]["manage"] = true if permissions.dig("whatsapp_campaigns", "manage")
      permissions["whatsapp_response_flows"]["scope"] ||= permissions.dig("whatsapp_campaigns", "scope") if permissions.dig("whatsapp_campaigns", "scope")
      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end

  def down
    AccessProfile.find_each do |profile|
      permissions = (profile.permissions || {}).deep_dup
      next unless permissions.key?("whatsapp_response_flows")

      permissions.delete("whatsapp_response_flows")
      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end
end
