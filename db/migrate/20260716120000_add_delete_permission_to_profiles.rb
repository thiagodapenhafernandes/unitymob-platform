# Fase 1 da granularidade de permissões: `delete` deixa de estar embutido em
# `manage` e vira ação própria em Imóveis e Leads.
#
# Backfill CONSERVADOR — grava `false` em todo perfil não-admin, em vez de tentar
# reproduzir a regra antiga (`manage && scope == "all"`). Motivo: a regra antiga
# é avaliada por USUÁRIO, combinando perfil vertical + horizontal, e o escopo
# efetivo é o MAIS RESTRITIVO dos dois (Profile.restricted_scope). Como
# AdminUser#can? concede a ação se QUALQUER um dos dois perfis tiver, gravar
# `delete = manage && scope == "all"` por perfil ALARGARIA acesso: um usuário
# Gerente (escopo "equipe") + Administrativo (escopo "todos") não exclui hoje,
# mas passaria a excluir pelo perfil horizontal.
#
# Excluir é destrutivo: preferimos estreitar e deixar o tenant religar
# conscientemente na tela de perfis a alargar sem ninguém pedir. Só o
# Administrador (`admin => true`) segue excluindo, pois Profile#can? o
# curto-circuita antes de olhar o JSON.
class AddDeletePermissionToProfiles < ActiveRecord::Migration[7.1]
  class MigrationProfile < ApplicationRecord
    self.table_name = "profiles"
  end

  RESOURCE_KEYS = %w[imoveis leads].freeze

  def up
    MigrationProfile.reset_column_information

    MigrationProfile.find_each do |profile|
      permissions = profile.permissions.presence || {}
      next unless permissions.is_a?(Hash)
      next if permissions["admin"] == true

      permissions = permissions.deep_dup
      changed = false

      RESOURCE_KEYS.each do |resource_key|
        entry = permissions[resource_key]
        next unless entry.is_a?(Hash)
        next if entry.key?("delete") # idempotente: não sobrescreve escolha já feita

        entry["delete"] = false
        changed = true
      end

      profile.update_columns(permissions: permissions, updated_at: Time.current) if changed
    end
  end

  def down
    MigrationProfile.reset_column_information

    MigrationProfile.find_each do |profile|
      permissions = profile.permissions.presence || {}
      next unless permissions.is_a?(Hash)

      permissions = permissions.deep_dup
      changed = false

      RESOURCE_KEYS.each do |resource_key|
        entry = permissions[resource_key]
        next unless entry.is_a?(Hash) && entry.key?("delete")

        entry.delete("delete")
        changed = true
      end

      profile.update_columns(permissions: permissions, updated_at: Time.current) if changed
    end
  end
end
