class AddAssignmentModesToExternalLeadIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :external_lead_integrations, :sale_assignment_mode, :string, null: false, default: "c2s"
    add_column :external_lead_integrations, :rental_assignment_mode, :string, null: false, default: "c2s"
    add_check_constraint :external_lead_integrations, "sale_assignment_mode IN ('c2s', 'unitymob')", name: "external_leads_sale_assignment_mode"
    add_check_constraint :external_lead_integrations, "rental_assignment_mode IN ('c2s', 'unitymob')", name: "external_leads_rental_assignment_mode"
  end
end
