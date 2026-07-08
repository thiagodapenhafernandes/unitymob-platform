class AddLeadsStatusCreatedAtPropertyIndexes < ActiveRecord::Migration[7.1]
  # Índices para os caminhos quentes da lista/kanban de leads:
  # - (tenant_id, status): counts por status do leads#index;
  # - (tenant_id, created_at): filtros de período + ORDER BY paginado;
  # - (tenant_id, property_id): apply_property_filter (busca por imóvel e
  #   anti-join de "imóvel indisponível");
  # - parcial em status = 'Aguardando Aceite': Leads::PocketSweepJob roda
  #   cross-tenant a cada minuto (Lead.waiting_acceptance, sem tenant_id).
  INDEXES = [
    { columns: [:tenant_id, :status], name: "index_leads_on_tenant_id_and_status", options: {} },
    { columns: [:tenant_id, :created_at], name: "index_leads_on_tenant_id_and_created_at", options: {} },
    { columns: [:tenant_id, :property_id], name: "index_leads_on_tenant_id_and_property_id", options: {} },
    { columns: :status, name: "index_leads_on_status_waiting_acceptance",
      options: { where: "status = 'Aguardando Aceite'" } }
  ].freeze

  def up
    INDEXES.each do |index|
      next if index_exists?(:leads, index[:columns], name: index[:name])

      add_index :leads, index[:columns], name: index[:name], **index[:options]
    end
  end

  def down
    INDEXES.each do |index|
      remove_index :leads, name: index[:name] if index_exists?(:leads, index[:columns], name: index[:name])
    end
  end
end
