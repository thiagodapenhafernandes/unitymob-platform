# frozen_string_literal: true

class ReconcilePreviousLocalSchemaState < ActiveRecord::Migration[7.1]
  def change
    # Esta versão já aparece aplicada em bancos de ensaio/local anteriores, mas
    # o arquivo original não estava mais no checkout. Mantemos a migration vazia
    # para preservar a linha do tempo e evitar "NO FILE" no cutover.
  end
end
