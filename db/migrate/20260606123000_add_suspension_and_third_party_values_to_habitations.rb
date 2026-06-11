class AddSuspensionAndThirdPartyValuesToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :motivo_suspensao, :text
    add_column :habitations, :valor_alugado_terceiros_cents, :bigint
    add_column :habitations, :valor_vendido_terceiros_cents, :bigint
  end
end
