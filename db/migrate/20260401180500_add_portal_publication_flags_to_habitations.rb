class AddPortalPublicationFlagsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :publicar_imovelweb_2, :boolean, default: false, null: false
    add_column :habitations, :publicar_netimoveis_2, :boolean, default: false, null: false
    add_column :habitations, :publicar_lais_ai, :boolean, default: false, null: false
    add_column :habitations, :publicar_loft, :boolean, default: false, null: false
    add_column :habitations, :publicar_chaves_na_mao, :boolean, default: false, null: false
    add_column :habitations, :publicar_casa_mineira, :boolean, default: false, null: false
    add_column :habitations, :publicar_imovelweb, :boolean, default: false, null: false
    add_column :habitations, :publicar_viva_real_vrsync, :boolean, default: false, null: false

    add_index :habitations, :publicar_imovelweb_2
    add_index :habitations, :publicar_netimoveis_2
    add_index :habitations, :publicar_lais_ai
    add_index :habitations, :publicar_loft
    add_index :habitations, :publicar_chaves_na_mao
    add_index :habitations, :publicar_casa_mineira
    add_index :habitations, :publicar_imovelweb
    add_index :habitations, :publicar_viva_real_vrsync
  end
end
