# frozen_string_literal: true

class ChangeProposalMoneyCentsToBigint < ActiveRecord::Migration[7.1]
  def change
    change_column :proposals, :valor_cents, :bigint, null: false, default: 0
    change_column :proposals, :entrada_cents, :bigint, null: false, default: 0
  end
end
