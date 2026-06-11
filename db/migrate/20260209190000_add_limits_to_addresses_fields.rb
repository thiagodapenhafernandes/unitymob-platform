class AddLimitsToAddressesFields < ActiveRecord::Migration[7.1]
  def change
    change_column :addresses, :uf, :string, limit: 2
    change_column :addresses, :cep, :string, limit: 10
  end
end
