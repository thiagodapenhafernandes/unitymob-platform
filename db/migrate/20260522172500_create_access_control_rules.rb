class CreateAccessControlRules < ActiveRecord::Migration[7.1]
  def change
    create_table :access_control_rules do |t|
      t.string :name, null: false
      t.string :rule_type, null: false
      t.string :scope_type, null: false, default: "global"
      t.references :profile, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :admin_users }
      t.string :ip_value, null: false
      t.boolean :enabled, null: false, default: true
      t.text :description
      t.timestamps
    end

    add_index :access_control_rules, :rule_type
    add_index :access_control_rules, :scope_type
    add_index :access_control_rules, :enabled
    add_index :access_control_rules, [:rule_type, :scope_type, :enabled], name: "index_access_rules_on_type_scope_enabled"
  end
end
