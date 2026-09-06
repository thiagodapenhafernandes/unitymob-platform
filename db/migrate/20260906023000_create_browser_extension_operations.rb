class CreateBrowserExtensionOperations < ActiveRecord::Migration[7.1]
  def change
    create_table :browser_extension_operations do |t|
      t.references :browser_extension_grant, null: false, foreign_key: true, index: false
      t.uuid :request_key, null: false
      t.string :request_digest, null: false
      t.jsonb :result, null: false
      t.timestamps
    end
    add_index :browser_extension_operations, [:browser_extension_grant_id, :request_key], unique: true, name: "idx_extension_operations_request"
  end
end
