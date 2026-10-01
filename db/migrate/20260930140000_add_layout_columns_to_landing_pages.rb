# Colunas do conteúdo da página (1 a 3). Padrão 1 = página como sempre foi (uma pilha de blocos).
class AddLayoutColumnsToLandingPages < ActiveRecord::Migration[7.1]
  def change
    add_column :landing_pages, :layout_columns, :integer, null: false, default: 1
    add_check_constraint :landing_pages, "layout_columns BETWEEN 1 AND 3", name: "landing_pages_layout_columns_range"
  end
end
