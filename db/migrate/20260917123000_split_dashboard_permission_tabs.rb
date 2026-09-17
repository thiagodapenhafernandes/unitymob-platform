class SplitDashboardPermissionTabs < ActiveRecord::Migration[7.1]
  DASHBOARD_TAB_KEYS = %w[
    dashboard_leads
    dashboard_properties
    dashboard_site
    dashboard_overview
    dashboard_field
  ].freeze

  def up
    Profile.find_each do |profile|
      permissions = profile.permissions || {}
      next unless permissions.dig("dashboard", "view") == true

      DASHBOARD_TAB_KEYS.each do |key|
        permissions[key] ||= {}
        permissions[key]["view"] = true if permissions[key]["view"].nil?
      end

      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end

  def down
    Profile.find_each do |profile|
      permissions = profile.permissions || {}
      DASHBOARD_TAB_KEYS.each { |key| permissions.delete(key) }
      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end
end
