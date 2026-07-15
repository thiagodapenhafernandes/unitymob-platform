class SyncProfileFieldLocksWithActiveHabitationForm < ActiveRecord::Migration[7.1]
  NEW_LOCK_KEYS = %w[
    cep apply_photo_watermark
    acao:buscar_cep acao:gerenciar_imediacoes acao:gerenciar_destaques
    acao:cadastrar_proprietario
    acao:remover_fichas_cadastro acao:remover_autorizacoes_venda
  ].freeze

  def up
    Profile.reset_column_information

    Profile.find_each do |profile|
      permissions = (profile.permissions || {}).deep_dup
      property_permissions = permissions["imoveis"]
      next unless property_permissions.is_a?(Hash)

      locked_fields = property_permissions["locked_fields"]
      next unless locked_fields.is_a?(Array)

      # Lista vazia é a configuração explícita de acesso integral do perfil.
      next if locked_fields.empty?

      property_permissions["locked_fields"] = (
        locked_fields.map(&:to_s) & Habitations::CadastroFieldRegistry.all_keys
      ).union(NEW_LOCK_KEYS)
      profile.update_column(:permissions, permissions)
    end
  end

  def down
    Profile.reset_column_information

    Profile.find_each do |profile|
      permissions = (profile.permissions || {}).deep_dup
      property_permissions = permissions["imoveis"]
      next unless property_permissions.is_a?(Hash) && property_permissions["locked_fields"].is_a?(Array)

      property_permissions["locked_fields"] -= NEW_LOCK_KEYS
      profile.update_column(:permissions, permissions)
    end
  end
end
