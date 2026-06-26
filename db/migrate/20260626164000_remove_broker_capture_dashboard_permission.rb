class RemoveBrokerCaptureDashboardPermission < ActiveRecord::Migration[7.1]
  def up
    broker_profiles.find_each do |profile|
      permissions = profile.permissions.to_h
      next unless permissions.key?("captacao_dashboard")

      permissions.delete("captacao_dashboard")
      profile.update_column(:permissions, permissions)
    end
  end

  def down
    broker_profiles.find_each do |profile|
      permissions = profile.permissions.to_h
      permissions["captacao_dashboard"] = { "view" => true }
      profile.update_column(:permissions, permissions)
    end
  end

  private

  def broker_profiles
    Profile.where(key: "corretor").or(Profile.where(name: "Corretor"))
  end
end
