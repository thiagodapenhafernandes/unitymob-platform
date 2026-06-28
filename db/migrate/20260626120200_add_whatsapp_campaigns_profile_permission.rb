class AddWhatsappCampaignsProfilePermission < ActiveRecord::Migration[7.1]
  def up
    update_profile!("Administrativo", "all")
    update_profile!("Gerente", "team")
  end

  def down
    Profile.where(name: ["Administrativo", "Gerente"]).find_each do |profile|
      permissions = profile.permissions.to_h
      permissions.delete("whatsapp_campaigns")
      profile.update_column(:permissions, permissions)
    end
  end

  private

  def update_profile!(name, scope)
    profile = Profile.find_by(name: name)
    return unless profile

    permissions = profile.permissions.to_h
    permissions["whatsapp_campaigns"] = { "view" => true, "manage" => true, "scope" => scope }
    profile.update_column(:permissions, permissions)
  end
end
