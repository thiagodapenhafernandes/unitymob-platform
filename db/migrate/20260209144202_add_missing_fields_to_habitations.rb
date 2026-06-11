class AddMissingFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :exclusivo_flag, :boolean
    add_column :habitations, :ocupacao_status, :string
    add_column :habitations, :estado_conservacao, :string
    add_column :habitations, :andar, :integer
    add_column :habitations, :ano_construcao, :integer
    add_column :habitations, :demi_suites_qtd, :integer
    add_column :habitations, :numero_box, :string
    add_column :habitations, :dimensoes_terreno, :string
    add_column :habitations, :topografia, :string
    add_column :habitations, :foto_classificacao, :string
    add_column :habitations, :podcast_url, :string
  end
end
