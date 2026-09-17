class SplitProductLeadMenuPermissions < ActiveRecord::Migration[7.1]
  LEAD_MENU_KEYS = %w[
    lead_pool
    lead_funnels
    lead_funnel_rental
    lead_funnel_sale
  ].freeze

  def up
    Profile.find_each do |profile|
      permissions = profile.permissions || {}
      leads = permissions["leads"]
      next unless leads.is_a?(Hash) && leads["view"] == true

      permissions["lead_pool"] ||= {}
      permissions["lead_pool"]["view"] = true if permissions["lead_pool"]["view"].nil?
      permissions["lead_pool"]["scope"] ||= leads["scope"] if leads["scope"].present?

      (LEAD_MENU_KEYS - ["lead_pool"]).each do |key|
        permissions[key] ||= {}
        permissions[key]["view"] = true if permissions[key]["view"].nil?
      end

      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end

  def down
    Profile.find_each do |profile|
      permissions = profile.permissions || {}
      LEAD_MENU_KEYS.each { |key| permissions.delete(key) }
      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end
end
