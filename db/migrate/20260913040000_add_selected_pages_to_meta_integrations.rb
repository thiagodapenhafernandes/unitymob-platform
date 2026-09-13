class AddSelectedPagesToMetaIntegrations < ActiveRecord::Migration[7.1]
  def up
    add_column :user_meta_integrations, :selected_page_ids, :jsonb, null: false, default: []
    execute <<~SQL
      UPDATE user_meta_integrations i SET selected_page_ids = (
        SELECT COALESCE(jsonb_agg(DISTINCT p.page_id), '[]'::jsonb)
        FROM meta_facebook_pages p WHERE p.user_meta_integration_id = i.id AND p.active = TRUE
      )
    SQL
  end

  def down
    remove_column :user_meta_integrations, :selected_page_ids
  end
end
