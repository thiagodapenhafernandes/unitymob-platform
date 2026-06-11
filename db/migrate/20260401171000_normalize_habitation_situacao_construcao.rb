class NormalizeHabitationSituacaoConstrucao < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE habitations
      SET situacao = 'Construção'
      WHERE situacao IN ('Em Obras', 'em obras');
    SQL
  end

  def down
    execute <<~SQL
      UPDATE habitations
      SET situacao = 'Em Obras'
      WHERE situacao = 'Construção';
    SQL
  end
end
