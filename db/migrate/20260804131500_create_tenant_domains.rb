class CreateTenantDomains < ActiveRecord::Migration[7.1]
  def change
    create_table :tenant_domains do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :hostname, null: false
      t.boolean :primary_domain, null: false, default: false
      t.boolean :active, null: false, default: true
      t.string :ssl_mode, null: false, default: "not_configured"
      t.datetime :verified_at
      t.text :notes

      t.timestamps
    end

    add_index :tenant_domains, "lower(hostname)", unique: true, name: "index_tenant_domains_on_lower_hostname"
    add_index :tenant_domains, [:tenant_id], unique: true, where: "primary_domain = true", name: "index_tenant_domains_on_primary_per_tenant"
    add_index :tenant_domains, [:tenant_id, :active]
  end
end
