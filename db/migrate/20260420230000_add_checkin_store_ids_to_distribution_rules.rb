class AddCheckinStoreIdsToDistributionRules < ActiveRecord::Migration[7.1]
  def up
    add_column :distribution_rules, :checkin_store_ids, :bigint, array: true, default: [], null: false
    add_index :distribution_rules, :checkin_store_ids, using: :gin

    # Migra dados existentes: se a regra tem checkin_store_id, copia pra array
    execute <<~SQL
      UPDATE distribution_rules
         SET checkin_store_ids = ARRAY[checkin_store_id]
       WHERE checkin_store_id IS NOT NULL
    SQL
  end

  def down
    remove_index :distribution_rules, :checkin_store_ids
    remove_column :distribution_rules, :checkin_store_ids
  end
end
