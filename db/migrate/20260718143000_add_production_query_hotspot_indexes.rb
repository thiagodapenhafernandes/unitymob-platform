class AddProductionQueryHotspotIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  SEO_PUBLIC_LINKS_INDEX = :idx_seo_settings_public_links_order
  SEO_PUBLIC_CANONICAL_INDEX = :idx_seo_settings_public_canonical
  HABITATIONS_PUBLIC_FILTER_INDEX = :idx_habitations_public_filter_price

  def up
    unless index_exists?(:seo_settings, [:tenant_id, :active, :apply_to_public, :robots_index, :page_type, :access_count, :last_accessed_at, :seo_score], name: SEO_PUBLIC_LINKS_INDEX)
      add_index :seo_settings,
                [:tenant_id, :active, :apply_to_public, :robots_index, :page_type, :access_count, :last_accessed_at, :seo_score],
                name: SEO_PUBLIC_LINKS_INDEX,
                order: { access_count: :desc, last_accessed_at: :desc, seo_score: :desc },
                algorithm: :concurrently
    end

    unless index_exists?(:seo_settings, [:tenant_id, :canonical_path], name: SEO_PUBLIC_CANONICAL_INDEX)
      add_index :seo_settings,
                [:tenant_id, :canonical_path],
                name: SEO_PUBLIC_CANONICAL_INDEX,
                algorithm: :concurrently
    end

    unless index_exists?(:habitations, [:tenant_id, :exibir_no_site_flag, :status, :tipo, :valor_venda_cents, :valor_locacao_cents], name: HABITATIONS_PUBLIC_FILTER_INDEX)
      add_index :habitations,
                [:tenant_id, :exibir_no_site_flag, :status, :tipo, :valor_venda_cents, :valor_locacao_cents],
                name: HABITATIONS_PUBLIC_FILTER_INDEX,
                algorithm: :concurrently
    end
  end

  def down
    remove_index :habitations, name: HABITATIONS_PUBLIC_FILTER_INDEX, algorithm: :concurrently, if_exists: true
    remove_index :seo_settings, name: SEO_PUBLIC_CANONICAL_INDEX, algorithm: :concurrently, if_exists: true
    remove_index :seo_settings, name: SEO_PUBLIC_LINKS_INDEX, algorithm: :concurrently, if_exists: true
  end
end
