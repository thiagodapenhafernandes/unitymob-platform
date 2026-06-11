class AddSaleReasonToHabitationsAndAttributeOptions < ActiveRecord::Migration[7.1]
  class MigrationAttributeOption < ApplicationRecord
    self.table_name = "attribute_options"
  end

  def up
    add_column :habitations, :motivo_venda, :string unless column_exists?(:habitations, :motivo_venda)

    reasons = []
    reasons += select_values("SELECT DISTINCT motivo_venda FROM habitations WHERE NULLIF(TRIM(motivo_venda), '') IS NOT NULL") if column_exists?(:habitations, :motivo_venda)
    reasons += select_values("SELECT DISTINCT motivo_venda FROM captacoes WHERE NULLIF(TRIM(motivo_venda), '') IS NOT NULL") if table_exists?(:captacoes) && column_exists?(:captacoes, :motivo_venda)

    fallback_reasons = [
      "Mudança",
      "Investimento",
      "Compra de outro imóvel",
      "Necessidade financeira",
      "Herança",
      "Divórcio",
      "Imóvel desocupado",
      "Outro"
    ]

    (reasons + fallback_reasons).map { |reason| reason.to_s.strip }.reject(&:blank?).uniq.each do |reason|
      MigrationAttributeOption.find_or_create_by!(
        context: "habitation",
        category: "sale_reason",
        name: reason
      )
    end
  end

  def down
    MigrationAttributeOption.where(context: "habitation", category: "sale_reason").delete_all
    remove_column :habitations, :motivo_venda if column_exists?(:habitations, :motivo_venda)
  end
end
