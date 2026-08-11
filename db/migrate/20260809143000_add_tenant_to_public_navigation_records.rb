class AddTenantToPublicNavigationRecords < ActiveRecord::Migration[7.1]
  def change
    add_reference :public_navigation_sessions, :tenant, foreign_key: true, index: true
    add_reference :public_navigation_events, :tenant, foreign_key: true, index: true

    add_index :public_navigation_events, [:tenant_id, :name, :occurred_at], name: "idx_public_nav_events_tenant_name_time"
    add_index :public_navigation_events, [:tenant_id, :path, :occurred_at], name: "idx_public_nav_events_tenant_path_time"
  end
end
