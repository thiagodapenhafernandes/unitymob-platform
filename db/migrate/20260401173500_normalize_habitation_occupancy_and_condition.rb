class NormalizeHabitationOccupancyAndCondition < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE habitations
      SET ocupacao_status = 'Desocupado'
      WHERE ocupacao_status IN ('Vago', 'vago');
    SQL

    execute <<~SQL
      UPDATE habitations
      SET estado_conservacao = 'Usado'
      WHERE estado_conservacao IN ('Depredado', 'depredado');
    SQL
  end

  def down
    execute <<~SQL
      UPDATE habitations
      SET ocupacao_status = 'Vago'
      WHERE ocupacao_status = 'Desocupado';
    SQL

    execute <<~SQL
      UPDATE habitations
      SET estado_conservacao = 'Depredado'
      WHERE estado_conservacao = 'Usado';
    SQL
  end
end
