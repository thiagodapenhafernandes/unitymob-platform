class AddRegistrationProfileToHabitations < ActiveRecord::Migration[7.1]
  CATEGORY_PROFILE_SQL = <<~SQL.squish
    CASE
      WHEN tipo = 'Empreendimento' OR categoria = 'Empreendimento' THEN 'empreendimento'
      WHEN categoria IN ('Apartamento', 'Cobertura', 'Loft', 'Studio') THEN 'apartamentos'
      WHEN categoria IN ('Terreno', 'Terreno em Condomínio', 'Área', 'Terreno Comercial', 'Terreno Industrial') THEN 'terrenos'
      WHEN categoria IN ('Sala Comercial', 'Loja', 'Prédio Comercial', 'Galpão', 'Galpão Industrial', 'Casa comercial', 'Condomínio Industrial', 'Ponto Comercial', 'Salas/Conjuntos') THEN 'comerciais_industriais'
      WHEN categoria IN ('Casa', 'Casa em Condomínio', 'Sobrado', 'Rural', 'Condomínio', 'Chácara', 'Sítio') THEN 'imoveis_residenciais'
      ELSE 'imoveis_residenciais'
    END
  SQL

  def up
    add_column :habitations, :registration_profile, :string unless column_exists?(:habitations, :registration_profile)
    add_index :habitations, :registration_profile unless index_exists?(:habitations, :registration_profile)

    execute <<~SQL.squish
      UPDATE habitations
         SET registration_profile = #{CATEGORY_PROFILE_SQL}
       WHERE registration_profile IS NULL OR TRIM(registration_profile) = ''
    SQL
  end

  def down
    remove_index :habitations, :registration_profile if index_exists?(:habitations, :registration_profile)
    remove_column :habitations, :registration_profile if column_exists?(:habitations, :registration_profile)
  end
end
