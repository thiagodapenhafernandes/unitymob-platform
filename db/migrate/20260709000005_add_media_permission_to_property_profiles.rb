class AddMediaPermissionToPropertyProfiles < ActiveRecord::Migration[7.1]
  class MigrationProfile < ApplicationRecord
    self.table_name = "profiles"
  end

  def up
    MigrationProfile.reset_column_information

    MigrationProfile.find_each do |profile|
      permissions = profile.permissions.presence || {}
      next unless permissions.is_a?(Hash)
      next if permissions["admin"] == true
      next unless permissions["imoveis"].is_a?(Hash)
      next if permissions["imoveis"].key?("media")

      permissions = permissions.deep_dup
      imoveis_permissions = permissions["imoveis"]
      imoveis_permissions["media"] = imoveis_permissions["view"] == true || imoveis_permissions["manage"] == true

      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end

  def down
    MigrationProfile.reset_column_information

    MigrationProfile.find_each do |profile|
      permissions = profile.permissions.presence || {}
      next unless permissions.is_a?(Hash)
      next unless permissions["imoveis"].is_a?(Hash)

      permissions = permissions.deep_dup
      permissions["imoveis"].delete("media")

      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end
end
