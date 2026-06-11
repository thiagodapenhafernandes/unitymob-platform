class CreateCaptacaoGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :captacao_goals do |t|
      t.integer :year,   null: false
      t.integer :kind,   null: false   # enum venda/locacao
      t.integer :target, null: false
      t.string  :foco_regiao
      t.decimal :foco_valor_min, precision: 12, scale: 2
      t.decimal :foco_valor_max, precision: 12, scale: 2
      t.timestamps
    end

    add_index :captacao_goals, [:year, :kind], unique: true
  end
end
