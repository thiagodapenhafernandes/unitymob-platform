# frozen_string_literal: true

# Serve a aba "verify" do kanban e a Conciliação: o scope unverified_inquiries
# filtra por flag JSONB e, sem índice, faz seq scan + detoast em leads (~5s em
# produção por contagem). Índice parcial cobre só as linhas não verificadas.
class AddPartialIndexForUnverifiedLeadInquiries < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :leads, %i[tenant_id lead_pipeline_id],
      name: "idx_leads_unverified_inquiries",
      where: "(other_information ->> 'unverified_inquiry') = 'true'",
      algorithm: :concurrently
  end

  def down
    remove_index :leads, name: "idx_leads_unverified_inquiries", algorithm: :concurrently
  end
end
