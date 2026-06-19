class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      t.references :lead, null: true, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true # responsável
      t.bigint :created_by_id
      t.string :title, null: false
      t.text :description
      t.string :kind, null: false, default: "follow_up"
      t.datetime :due_at
      t.datetime :completed_at
      t.string :status, null: false, default: "pendente"
      t.string :priority, null: false, default: "normal"

      t.timestamps
    end

    add_index :tasks, [:admin_user_id, :status]
    add_index :tasks, :due_at
    add_index :tasks, :created_by_id
  end
end
