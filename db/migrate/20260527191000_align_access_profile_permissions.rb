class AlignAccessProfilePermissions < ActiveRecord::Migration[7.1]
  def up
    update_profile!("Administrativo") do |permissions|
      permissions["dashboard"] = { "view" => true }
      permissions["imoveis"] = { "view" => true, "manage" => true, "scope" => "all" }
      permissions["leads"] = { "view" => true, "manage" => true, "scope" => "all" }
      permissions["captacoes"] = { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "all" }
      permissions["captacao_dashboard"] = { "view" => true }
    end

    update_profile!("Gerente") do |permissions|
      permissions["dashboard"] = { "view" => true }
      permissions["imoveis"] = { "view" => true, "manage" => true, "scope" => "all" }
      permissions["leads"] = { "view" => true, "manage" => true, "scope" => "all" }
      permissions["captacoes"] = { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "all" }
      permissions["captacao_dashboard"] = { "view" => true }
      permissions.delete("proprietarios")
      permissions.delete("agenda_fotografia")
      permissions.delete("marketing")
      permissions.delete("data_export_audit")
    end
  end

  def down
    update_profile!("Administrativo") do |permissions|
      permissions.delete("leads")
    end

    update_profile!("Gerente") do |permissions|
      permissions["agenda_fotografia"] = { "view" => true, "manage" => true }
      permissions["marketing"] = { "manage" => true }
    end
  end

  private

  def update_profile!(name)
    profile = Profile.find_by(name: name)
    return unless profile

    permissions = profile.permissions.to_h
    yield permissions
    profile.update!(permissions: permissions)
  end
end
