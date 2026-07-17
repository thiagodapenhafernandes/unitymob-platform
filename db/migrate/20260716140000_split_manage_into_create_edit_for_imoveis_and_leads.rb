# Fase 2 da granularidade: `manage` (criar + editar juntos) é desmembrado em
# `create` e `edit` para Imóveis e Leads.
#
# Backfill de PRESERVAÇÃO EXATA: create = edit = manage. Diferente da Fase 1
# (delete), aqui não há risco de alargar acesso — a regra antiga era só
# `can?(:manage, X)`, sem escopo no meio, e AdminUser#can? é o OR dos dois
# perfis. Como cada perfil herda o próprio manage, o OR resultante é idêntico:
#
#   depois: can?(:edit)   = vertical.manage || horizontal.manage
#   antes:  can?(:manage) = vertical.manage || horizontal.manage
#
# Leads não recebe `create`: o admin não cadastra lead (a rota de create é do
# site público), então o switch não existiria para nada.
#
# A chave `manage` fica no JSON de propósito: torna o rollback trivial e nada
# mais a lê nestes dois recursos. Ela some sozinha no primeiro save do perfil
# pela tela, porque profile_params_with_permissions reconstrói o hash a partir
# de Profile::RESOURCES.
class SplitManageIntoCreateEditForImoveisAndLeads < ActiveRecord::Migration[7.1]
  class MigrationProfile < ApplicationRecord
    self.table_name = "profiles"
  end

  # resource => ações derivadas de manage
  DERIVED_ACTIONS = {
    "imoveis" => %w[create edit],
    "leads"   => %w[edit]
  }.freeze

  def up
    MigrationProfile.reset_column_information

    MigrationProfile.find_each do |profile|
      permissions = profile.permissions.presence || {}
      next unless permissions.is_a?(Hash)
      next if permissions["admin"] == true # full access curto-circuita o JSON

      permissions = permissions.deep_dup
      changed = false

      DERIVED_ACTIONS.each do |resource_key, actions|
        entry = permissions[resource_key]
        next unless entry.is_a?(Hash)

        manage = entry["manage"] == true
        actions.each do |action|
          next if entry.key?(action) # idempotente: respeita escolha já feita

          entry[action] = manage
          changed = true
        end
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

      DERIVED_ACTIONS.each do |resource_key, actions|
        entry = permissions[resource_key]
        next unless entry.is_a?(Hash)

        # Reconstrói manage a partir das ações derivadas para perfis que já
        # tenham perdido a chave (save pela tela após a Fase 2).
        entry["manage"] = actions.any? { |action| entry[action] == true } unless entry.key?("manage")

        actions.each do |action|
          next unless entry.key?(action)

          entry.delete(action)
          changed = true
        end
      end

      profile.update_columns(permissions: permissions, updated_at: Time.current) if changed
    end
  end
end
