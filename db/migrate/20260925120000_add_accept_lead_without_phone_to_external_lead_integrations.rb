# frozen_string_literal: true

class AddAcceptLeadWithoutPhoneToExternalLeadIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :external_lead_integrations, :accept_lead_without_phone, :boolean, default: false, null: false
  end
end
