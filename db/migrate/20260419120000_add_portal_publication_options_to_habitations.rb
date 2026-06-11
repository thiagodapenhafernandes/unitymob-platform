class AddPortalPublicationOptionsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :destaque_chaves_na_mao, :string
    add_column :habitations, :periodo_locacao_chaves_na_mao, :string

    add_column :habitations, :modelo_casa_mineira, :string

    add_column :habitations, :tipo_publicacao_viva_real, :string
    add_column :habitations, :divulgar_endereco_viva_real, :string

    add_column :habitations, :tipo_publicacao_imovelweb, :string
    add_column :habitations, :mostrar_mapa_imovelweb, :string

    add_column :habitations, :tipo_publicacao_imovelweb_2, :string
    add_column :habitations, :mostrar_mapa_imovelweb_2, :string
  end
end
