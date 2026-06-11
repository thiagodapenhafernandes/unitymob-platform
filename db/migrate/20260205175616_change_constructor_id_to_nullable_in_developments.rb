class ChangeConstructorIdToNullableInDevelopments < ActiveRecord::Migration[7.1]
  def change
    change_column_null :developments, :constructor_id, true
  end
end
