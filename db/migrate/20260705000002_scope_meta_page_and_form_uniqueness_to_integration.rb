class ScopeMetaPageAndFormUniquenessToIntegration < ActiveRecord::Migration[7.1]
  # Modelo agência: a MESMA página do Facebook pode ser conectada por
  # integrações de contas diferentes. O unique GLOBAL de page_id/form_id
  # impedia isso — passa a ser único por integração/página.
  #
  # Seguro em dados existentes: o unique global antigo é estritamente mais
  # forte que o composto novo, então o add_index nunca falha.
  #
  # ATENÇÃO (rollback): o down FALHA se já existirem dados de agência (mesma
  # página em 2+ integrações) — intencional; exigiria dedupe manual antes.
  def up
    if index_exists?(:meta_facebook_pages, :page_id, name: :index_meta_facebook_pages_on_page_id)
      remove_index :meta_facebook_pages, name: :index_meta_facebook_pages_on_page_id
    end
    unless index_exists?(:meta_facebook_pages, [:user_meta_integration_id, :page_id], name: :idx_meta_pages_on_integration_and_page_id)
      add_index :meta_facebook_pages, [:user_meta_integration_id, :page_id],
                unique: true, name: :idx_meta_pages_on_integration_and_page_id
    end

    if index_exists?(:meta_lead_forms, :form_id, name: :index_meta_lead_forms_on_form_id)
      remove_index :meta_lead_forms, name: :index_meta_lead_forms_on_form_id
    end
    unless index_exists?(:meta_lead_forms, [:meta_facebook_page_id, :form_id], name: :idx_meta_forms_on_page_and_form_id)
      add_index :meta_lead_forms, [:meta_facebook_page_id, :form_id],
                unique: true, name: :idx_meta_forms_on_page_and_form_id
    end

    # Consulta por page_id continua frequente (webhook de leads) — índice simples.
    unless index_exists?(:meta_facebook_pages, :page_id, name: :idx_meta_pages_on_page_id)
      add_index :meta_facebook_pages, :page_id, name: :idx_meta_pages_on_page_id
    end
  end

  def down
    remove_index :meta_facebook_pages, name: :idx_meta_pages_on_page_id if index_exists?(:meta_facebook_pages, :page_id, name: :idx_meta_pages_on_page_id)

    if index_exists?(:meta_lead_forms, [:meta_facebook_page_id, :form_id], name: :idx_meta_forms_on_page_and_form_id)
      remove_index :meta_lead_forms, name: :idx_meta_forms_on_page_and_form_id
    end
    unless index_exists?(:meta_lead_forms, :form_id, name: :index_meta_lead_forms_on_form_id)
      add_index :meta_lead_forms, :form_id, unique: true, name: :index_meta_lead_forms_on_form_id
    end

    if index_exists?(:meta_facebook_pages, [:user_meta_integration_id, :page_id], name: :idx_meta_pages_on_integration_and_page_id)
      remove_index :meta_facebook_pages, name: :idx_meta_pages_on_integration_and_page_id
    end
    unless index_exists?(:meta_facebook_pages, :page_id, name: :index_meta_facebook_pages_on_page_id)
      add_index :meta_facebook_pages, :page_id, unique: true, name: :index_meta_facebook_pages_on_page_id
    end
  end
end
