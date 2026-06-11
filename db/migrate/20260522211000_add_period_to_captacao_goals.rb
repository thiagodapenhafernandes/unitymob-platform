class AddPeriodToCaptacaoGoals < ActiveRecord::Migration[7.1]
  def up
    add_column :captacao_goals, :start_date, :date
    add_column :captacao_goals, :end_date, :date

    execute <<~SQL.squish
      UPDATE captacao_goals
         SET start_date = make_date(year, 1, 1),
             end_date = make_date(year, 12, 31)
       WHERE start_date IS NULL OR end_date IS NULL
    SQL

    change_column_null :captacao_goals, :start_date, false
    change_column_null :captacao_goals, :end_date, false

    remove_index :captacao_goals, name: :index_captacao_goals_on_year_and_kind
    add_index :captacao_goals, [:kind, :start_date, :end_date], name: :index_captacao_goals_on_kind_and_period
  end

  def down
    remove_index :captacao_goals, name: :index_captacao_goals_on_kind_and_period
    add_index :captacao_goals, [:year, :kind], unique: true
    remove_column :captacao_goals, :end_date
    remove_column :captacao_goals, :start_date
  end
end
