class BackfillLeadNotesAsLeadActivities < ActiveRecord::Migration[7.1]
  BACKFILL_SOURCE = "lead_notes_backfill".freeze

  LeadRecord = Class.new(ActiveRecord::Base) do
    self.table_name = "leads"
  end

  LeadActivityRecord = Class.new(ActiveRecord::Base) do
    self.table_name = "lead_activities"
  end

  def up
    say_with_time "Backfilling lead notes into lead activities" do
      LeadRecord.reset_column_information
      LeadActivityRecord.reset_column_information

      lead_activity_columns = LeadActivityRecord.column_names
      has_tenant = lead_activity_columns.include?("tenant_id")
      has_source_category = lead_activity_columns.include?("source_category")

      LeadRecord.where.not(notes: [nil, ""]).find_each do |lead|
        next if backfilled_note_exists?(lead)

        attributes = {
          lead_id: lead.id,
          kind: "note",
          metadata: {
            "body" => lead.notes.to_s.strip,
            "by" => "Histórico existente",
            "source" => BACKFILL_SOURCE
          },
          created_at: lead.updated_at || Time.current,
          updated_at: Time.current
        }
        attributes[:tenant_id] = lead.tenant_id if has_tenant
        attributes[:source_category] = "human" if has_source_category

        LeadActivityRecord.create!(attributes)
      end
    end
  end

  def down
    LeadActivityRecord.where(kind: "note").where("metadata ->> 'source' = ?", BACKFILL_SOURCE).delete_all
  end

  private

  def backfilled_note_exists?(lead)
    LeadActivityRecord
      .where(lead_id: lead.id, kind: "note")
      .where("metadata ->> 'source' = ?", BACKFILL_SOURCE)
      .exists?
  end
end
