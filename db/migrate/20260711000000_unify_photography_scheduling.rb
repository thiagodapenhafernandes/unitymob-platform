class UnifyPhotographyScheduling < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE habitations
      SET photo_flow_choice = 'schedule'
      WHERE photo_flow_choice = 'google_calendar'
    SQL
  end

  def down
    # A origem antiga não pode ser reconstruída com segurança após a unificação.
  end
end
