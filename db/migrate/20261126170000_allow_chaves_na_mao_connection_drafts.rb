class AllowChavesNaMaoConnectionDrafts < ActiveRecord::Migration[7.1]
  def change
    change_column_null :chaves_na_mao_connections, :account_code, true
  end
end
