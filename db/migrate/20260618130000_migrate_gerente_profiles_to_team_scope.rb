class MigrateGerenteProfilesToTeamScope < ActiveRecord::Migration[7.1]
  # Perfis "Gerente" antigos guardavam scope "all" (viam TUDO). A governança por equipe
  # passa esse papel para o scope "team" (próprios + subárvore de gestão). Migra só os
  # perfis nomeados "Gerente"; "Administrador"/"Administrativo" continuam como estão.
  TEAM_RESOURCES = %w[imoveis leads comercial whatsapp_inbox captacoes].freeze

  def up
    remap_scope("all", "team")
  end

  def down
    remap_scope("team", "all")
  end

  private

  def remap_scope(from, to)
    Profile.where(name: "Gerente").find_each do |profile|
      perms = profile.permissions || {}
      changed = false
      TEAM_RESOURCES.each do |res|
        next unless perms[res].is_a?(Hash) && perms[res]["scope"] == from

        perms[res]["scope"] = to
        changed = true
      end
      profile.update_column(:permissions, perms) if changed
    end
  end
end
