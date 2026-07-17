# Cadastro manual de lead pelo admin: `create` passa a existir para Leads.
#
# Até aqui o admin não criava lead (só o site público/webhook), por isso a Fase 2
# deixou Leads sem `create`. Com a tela de cadastro, a ação existe e precisa ser
# configurável por perfil.
#
# Backfill: create = edit. Quem já podia editar lead é operador de lead e passa a
# poder cadastrar. É uma capacidade nova (não havia comportamento anterior a
# preservar), mas de baixo risco — cadastrar é entrada de dado, não é destrutivo
# como excluir, e o dono/escopo continuam mandando em quem mexe depois. Quem não
# quiser, desliga o switch na tela de perfis.
class AddLeadCreatePermissionToProfiles < ActiveRecord::Migration[7.1]
  class MigrationProfile < ApplicationRecord
    self.table_name = "profiles"
  end

  def up
    MigrationProfile.reset_column_information

    MigrationProfile.find_each do |profile|
      permissions = profile.permissions.presence || {}
      next unless permissions.is_a?(Hash)
      next if permissions["admin"] == true

      entry = permissions["leads"]
      next unless entry.is_a?(Hash)
      next if entry.key?("create") # idempotente

      permissions = permissions.deep_dup
      # `manage` cobre perfis que ainda não passaram pelo backfill da Fase 2.
      permissions["leads"]["create"] = entry["edit"] == true || entry["manage"] == true

      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end

  def down
    MigrationProfile.reset_column_information

    MigrationProfile.find_each do |profile|
      permissions = profile.permissions.presence || {}
      next unless permissions.is_a?(Hash)

      entry = permissions["leads"]
      next unless entry.is_a?(Hash) && entry.key?("create")

      permissions = permissions.deep_dup
      permissions["leads"].delete("create")

      profile.update_columns(permissions: permissions, updated_at: Time.current)
    end
  end
end
