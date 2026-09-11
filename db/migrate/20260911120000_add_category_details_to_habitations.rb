class AddCategoryDetailsToHabitations < ActiveRecord::Migration[7.1]
  MEASURES = %i[
    area_armazenagem_m2 pe_direito_livre_m
    altura_armazenagem_m capacidade_piso_ton_m2 capacidade_eletrica_kva
    lateral_1_terreno_m lateral_2_terreno_m
  ].freeze
  STRINGS = %i[
    outra_operacao_galpao setor_terreno
  ].freeze

  def change
    STRINGS.each { |name| add_column :habitations, name, :string }
    MEASURES.each do |name|
      add_column :habitations, name, :decimal, precision: 14, scale: 2
      add_check_constraint :habitations, "#{name} IS NULL OR #{name} > 0", name: "habitations_#{name}_positive"
    end
    add_column :habitations, :docas_qtd, :integer
    add_check_constraint :habitations, "docas_qtd IS NULL OR docas_qtd >= 0", name: "habitations_docas_qtd_nonnegative"
  end
end
