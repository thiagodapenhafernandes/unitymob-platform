class SeedProfileFieldLocks < ActiveRecord::Migration[7.1]
  # Card #1 / Opção B: a partir de agora "só o dono edita tudo; o resto é por
  # perfil". Semeia locked_fields em cada perfil existente PRESERVANDO o
  # comportamento atual, para a virada do gatilho não quebrar ninguém:
  #   - perfis full-access hoje (admin OU imoveis escopo "all") -> nada travado.
  #   - demais (restritos)                                       -> matriz do card #1.
  # Perfis que já tiverem locked_fields configurado são preservados.
  def up
    default_locked = Habitations::FieldLockPolicy.default_locked_keys.to_a

    Profile.reset_column_information
    Profile.find_each do |profile|
      perms = (profile.permissions || {}).deep_dup
      imoveis = perms["imoveis"].is_a?(Hash) ? perms["imoveis"] : {}
      next if imoveis["locked_fields"].is_a?(Array)

      full_access = perms["admin"] == true || imoveis["scope"] == "all"
      imoveis["locked_fields"] = full_access ? [] : default_locked
      perms["imoveis"] = imoveis
      profile.update_column(:permissions, perms)
    end
  end

  def down
    Profile.reset_column_information
    Profile.find_each do |profile|
      perms = profile.permissions
      next unless perms.is_a?(Hash) && perms["imoveis"].is_a?(Hash) && perms["imoveis"].key?("locked_fields")

      perms = perms.deep_dup
      perms["imoveis"].delete("locked_fields")
      profile.update_column(:permissions, perms)
    end
  end
end
