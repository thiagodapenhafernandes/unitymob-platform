class AddKeyToProfiles < ActiveRecord::Migration[7.1]
  # Identificador estável de papel do sistema, independente do nome (que vira rótulo livre).
  CANONICAL = {
    "Administrador"  => "administrador",
    "Diretor"        => "diretor",
    "Gerente"        => "gerente",
    "Administrativo" => "administrativo",
    "Corretor"       => "corretor"
  }.freeze

  def up
    add_column :profiles, :key, :string
    add_index :profiles, :key, unique: true, where: "key IS NOT NULL"

    # Backfill por nome canônico (nomes são únicos -> no máximo 1 linha por chave).
    CANONICAL.each do |name, key|
      execute(<<~SQL)
        UPDATE profiles SET key = #{connection.quote(key)}
        WHERE key IS NULL AND LOWER(name) = #{connection.quote(name.downcase)}
      SQL
    end
  end

  def down
    remove_index :profiles, :key
    remove_column :profiles, :key
  end
end
