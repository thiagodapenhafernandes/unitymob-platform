class AddPublicHabitationPerformanceIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  PUBLIC_ORDER_INDEX = "idx_habitations_public_tenant_status_order".freeze
  PUBLIC_DEVELOPMENT_UNITS_INDEX = "idx_habitations_public_development_units".freeze
  HABITATION_PHOTO_ATTACHMENTS_INDEX = "idx_active_storage_habitation_photo_records".freeze

  def up
    unless index_exists?(:habitations, [:tenant_id, :exibir_no_site_flag, :status, :data_atualizacao_crm, :created_at], name: PUBLIC_ORDER_INDEX)
      add_index :habitations,
                [:tenant_id, :exibir_no_site_flag, :status, :data_atualizacao_crm, :created_at],
                name: PUBLIC_ORDER_INDEX,
                order: { data_atualizacao_crm: :desc, created_at: :desc },
                algorithm: :concurrently
    end

    unless index_exists?(:habitations, [:tenant_id, :codigo_empreendimento, :exibir_no_site_flag, :status], name: PUBLIC_DEVELOPMENT_UNITS_INDEX)
      add_index :habitations,
                [:tenant_id, :codigo_empreendimento, :exibir_no_site_flag, :status],
                name: PUBLIC_DEVELOPMENT_UNITS_INDEX,
                where: "codigo_empreendimento IS NOT NULL",
                algorithm: :concurrently
    end

    unless index_exists?(:active_storage_attachments, [:record_type, :name, :record_id], name: HABITATION_PHOTO_ATTACHMENTS_INDEX)
      add_index :active_storage_attachments,
                [:record_type, :name, :record_id],
                name: HABITATION_PHOTO_ATTACHMENTS_INDEX,
                where: "record_type = 'Habitation' AND name = 'photos'",
                algorithm: :concurrently
    end
  end

  def down
    remove_index :active_storage_attachments, name: HABITATION_PHOTO_ATTACHMENTS_INDEX, algorithm: :concurrently, if_exists: true
    remove_index :habitations, name: PUBLIC_DEVELOPMENT_UNITS_INDEX, algorithm: :concurrently, if_exists: true
    remove_index :habitations, name: PUBLIC_ORDER_INDEX, algorithm: :concurrently, if_exists: true
  end
end
