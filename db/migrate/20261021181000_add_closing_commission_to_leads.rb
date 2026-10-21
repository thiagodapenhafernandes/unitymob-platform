class AddClosingCommissionToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :closing_commission_cents, :bigint
    add_check_constraint :leads, "closing_commission_cents BETWEEN 0 AND 999999999999", name: "leads_closing_commission_range"
  end
end
