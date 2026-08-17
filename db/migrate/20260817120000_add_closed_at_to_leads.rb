class AddClosedAtToLeads < ActiveRecord::Migration[7.1]
  def up
    add_column :leads, :closed_at, :datetime
    add_index :leads, [:tenant_id, :closed_at]

    execute <<~SQL.squish
      UPDATE leads
      SET closed_at = updated_at
      WHERE status = 'Concluido'
        AND closed_at IS NULL
    SQL
  end

  def down
    remove_index :leads, [:tenant_id, :closed_at]
    remove_column :leads, :closed_at
  end
end
