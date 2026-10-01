class AddStatusToPublicForms < ActiveRecord::Migration[7.1]
  # inactive | draft | published. `active` continua existindo (derivado: só "published" está no ar),
  # então todo o site público segue usando o scope .active sem mudança.
  def up
    add_column :public_forms, :status, :string, default: "published", null: false
    execute "UPDATE public_forms SET status = 'inactive' WHERE active = FALSE"
    add_index :public_forms, [:tenant_id, :status]
  end

  def down
    remove_index :public_forms, [:tenant_id, :status]
    remove_column :public_forms, :status
  end
end
