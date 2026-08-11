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
    rows = select_all(<<~SQL)
      SELECT id, permissions
      FROM profiles
      WHERE name = #{connection.quote(name)}
    SQL

    rows.each do |row|
      permissions = row["permissions"].presence || {}
      permissions = JSON.parse(permissions) if permissions.is_a?(String)
      permissions = permissions.to_h
      yield permissions

      execute(<<~SQL)
        UPDATE profiles
        SET permissions = #{connection.quote(permissions.to_json)}::jsonb,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = #{row["id"].to_i}
      SQL
    end
  end
end
