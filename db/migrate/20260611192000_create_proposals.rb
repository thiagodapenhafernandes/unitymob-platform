class CreateProposals < ActiveRecord::Migration[7.1]
  def change
    create_table :proposals do |t|
      t.references :lead, null: false, foreign_key: true
      t.references :habitation, null: true, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :public_token, null: false
      t.string :title
      t.integer :valor_cents, null: false, default: 0
      t.integer :entrada_cents, null: false, default: 0
      t.text :condicoes
      t.jsonb :extra, null: false, default: {}
      t.date :validade
      t.string :status, null: false, default: "rascunho"
      t.datetime :sent_at
      t.datetime :viewed_at
      t.datetime :responded_at

      t.timestamps
    end

    add_index :proposals, :public_token, unique: true
    add_index :proposals, [:lead_id, :status]
  end
end
