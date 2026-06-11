class ApplyAccessProfilePresets < ActiveRecord::Migration[7.1]
  PROFILE_NAMES = %w[Administrador Corretor Administrativo Gerente].freeze

  def up
    PROFILE_NAMES.each do |name|
      profile = Profile.find_or_initialize_by(name: name)
      profile.active = true
      profile.permissions = Profile.default_permissions_for(name)
      profile.save!
    end

    photographer = Profile.find_by(name: "Fotógrafo")
    administrative = Profile.find_by!(name: "Administrativo")

    if photographer
      AdminUser.where(profile_id: photographer.id).update_all(profile_id: administrative.id, updated_at: Time.current)
      photographer.destroy! if photographer.admin_users.reload.none?
    end
  end

  def down
    photographer = Profile.find_or_initialize_by(name: "Fotógrafo")
    photographer.active = true
    photographer.permissions = {
      "admin" => false,
      "dashboard" => { "view" => false },
      "agenda_fotografia" => { "view" => true, "manage" => false }
    }
    photographer.save!
  end
end
