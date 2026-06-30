class AddTenantToAttributeOptions < ActiveRecord::Migration[7.1]
  def up
    default_tenant_id = default_tenant

    add_reference :attribute_options, :tenant, foreign_key: true unless column_exists?(:attribute_options, :tenant_id)
    execute("UPDATE attribute_options SET tenant_id = #{default_tenant_id.to_i} WHERE tenant_id IS NULL")
    change_column_null :attribute_options, :tenant_id, false

    remove_index :attribute_options, name: "index_attribute_options_on_context_category_lower_name" if index_exists?(:attribute_options, nil, name: "index_attribute_options_on_context_category_lower_name")
    add_index :attribute_options,
              "tenant_id, lower(name), category, context",
              unique: true,
              name: "index_attribute_options_on_context_category_lower_name"

    remove_index :attribute_options, name: "index_attribute_options_on_context_category_position" if index_exists?(:attribute_options, nil, name: "index_attribute_options_on_context_category_position")
    add_index :attribute_options,
              [:tenant_id, :context, :category, :position],
              name: "index_attribute_options_on_context_category_position"
  end

  def down
    remove_index :attribute_options, name: "index_attribute_options_on_context_category_position" if index_exists?(:attribute_options, nil, name: "index_attribute_options_on_context_category_position")
    add_index :attribute_options,
              [:context, :category, :position],
              name: "index_attribute_options_on_context_category_position"

    remove_index :attribute_options, name: "index_attribute_options_on_context_category_lower_name" if index_exists?(:attribute_options, nil, name: "index_attribute_options_on_context_category_lower_name")
    add_index :attribute_options,
              "lower(name), category, context",
              unique: true,
              name: "index_attribute_options_on_context_category_lower_name"

    remove_reference :attribute_options, :tenant, foreign_key: true if column_exists?(:attribute_options, :tenant_id)
  end

  private

  def default_tenant
    select_value("SELECT id FROM tenants WHERE slug = 'default' LIMIT 1").presence ||
      select_value("INSERT INTO tenants (name, slug, active, created_at, updated_at) VALUES ('Conta principal', 'default', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
  end
end
