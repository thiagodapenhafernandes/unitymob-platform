class GrantCommercialContractsToAdministrativeProfiles < ActiveRecord::Migration[7.1]
  class AccessProfile < ApplicationRecord
    self.table_name = "profiles"
  end

  def up
    say_with_time "Grant commercial contracts permission to existing administrative profiles" do
      AccessProfile.where(key: "administrativo").find_each do |profile|
        permissions = (profile.permissions || {}).deep_dup
        permissions["commercial_contracts"] ||= {}
        permissions["commercial_contracts"]["manage"] = true
        profile.update_columns(permissions: permissions, updated_at: Time.current)
      end
    end
  end

  def down
    say_with_time "Remove commercial contracts permission from administrative profiles" do
      AccessProfile.where(key: "administrativo").find_each do |profile|
        permissions = (profile.permissions || {}).deep_dup
        next unless permissions["commercial_contracts"].is_a?(Hash)

        permissions["commercial_contracts"].delete("manage")
        permissions.delete("commercial_contracts") if permissions["commercial_contracts"].blank?
        profile.update_columns(permissions: permissions, updated_at: Time.current)
      end
    end
  end
end
