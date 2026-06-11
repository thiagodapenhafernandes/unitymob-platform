class AddPublicarZapimoveisToHabitations < ActiveRecord::Migration[7.1]
  def up
    add_column :habitations, :publicar_zapimoveis, :boolean, default: false, null: false
    add_index :habitations, :publicar_zapimoveis

    execute <<~SQL.squish
      UPDATE habitations
      SET publicar_zapimoveis = COALESCE(publicar_imovelweb_2, false)
    SQL
  end

  def down
    remove_index :habitations, :publicar_zapimoveis
    remove_column :habitations, :publicar_zapimoveis
  end
end
