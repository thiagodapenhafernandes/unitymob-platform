# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_20_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "postgis"
  enable_extension "unaccent"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "addressable_type", null: false
    t.bigint "addressable_id", null: false
    t.string "tipo_endereco"
    t.string "logradouro"
    t.string "numero"
    t.string "complemento"
    t.string "bairro"
    t.string "bairro_comercial"
    t.string "cidade"
    t.string "uf", limit: 2
    t.string "cep", limit: 10
    t.string "pais", default: "Brasil"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.text "imediacoes", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["addressable_type", "addressable_id"], name: "index_addresses_on_addressable"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "profile_id"
    t.bigint "manager_id"
    t.string "vista_id"
    t.string "creci"
    t.string "phone"
    t.text "biography"
    t.date "birth_date"
    t.string "city"
    t.integer "acting_type"
    t.boolean "field_agent_enabled", default: false, null: false
    t.bigint "default_store_id"
    t.index ["default_store_id"], name: "index_admin_users_on_default_store_id"
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["field_agent_enabled"], name: "index_admin_users_on_field_agent_enabled"
    t.index ["manager_id"], name: "index_admin_users_on_manager_id"
    t.index ["profile_id"], name: "index_admin_users_on_profile_id"
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
    t.index ["vista_id"], name: "index_admin_users_on_vista_id"
  end

  create_table "attribute_options", force: :cascade do |t|
    t.string "name", null: false
    t.string "category", null: false
    t.string "context", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text), category, context", name: "index_attribute_options_on_context_category_lower_name", unique: true
  end

  create_table "banners", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "link_url"
    t.string "link_text"
    t.boolean "active"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "positions", default: [], array: true
  end

  create_table "constructors", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "website_url"
  end

  create_table "contact_settings", force: :cascade do |t|
    t.string "whatsapp_primary"
    t.string "whatsapp_secondary"
    t.string "phone"
    t.string "email_primary"
    t.string "email_commercial"
    t.text "address"
    t.text "business_hours"
    t.string "facebook_url"
    t.string "instagram_url"
    t.string "youtube_url"
    t.string "linkedin_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "distribution_rule_agents", force: :cascade do |t|
    t.bigint "distribution_rule_id", null: false
    t.bigint "admin_user_id", null: false
    t.integer "weight", default: 1
    t.datetime "last_lead_received_at"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_distribution_rule_agents_on_admin_user_id"
    t.index ["distribution_rule_id", "admin_user_id"], name: "idx_dist_rule_agents_on_rule_and_admin", unique: true
    t.index ["distribution_rule_id"], name: "index_distribution_rule_agents_on_distribution_rule_id"
  end

  create_table "distribution_rules", force: :cascade do |t|
    t.string "name", null: false
    t.integer "business_type", default: 0
    t.boolean "source_meta", default: false
    t.boolean "source_webhook", default: false
    t.boolean "source_portal", default: false
    t.jsonb "meta_forms", default: []
    t.jsonb "webhook_tags", default: []
    t.jsonb "custom_filters", default: []
    t.integer "distribution_mode", default: 0
    t.boolean "pocket_active", default: false
    t.integer "pocket_time", default: 30
    t.boolean "represamento_active", default: false
    t.jsonb "represamento_schedule", default: {}
    t.boolean "active", default: true
    t.decimal "min_price", precision: 15, scale: 2
    t.decimal "max_price", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "source_site", default: false
    t.boolean "auto_add_forms", default: false
    t.boolean "notify_whatsapp", default: false
    t.boolean "notify_email", default: false
    t.boolean "notify_webhook", default: false
    t.jsonb "meta_page_ids", default: []
    t.jsonb "neighborhoods", default: []
    t.string "webhook_url"
  end

  create_table "footer_links", force: :cascade do |t|
    t.string "label"
    t.string "url"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "footer_setting_id", null: false
    t.index ["footer_setting_id"], name: "index_footer_links_on_footer_setting_id"
  end

  create_table "footer_settings", force: :cascade do |t|
    t.string "about_title"
    t.text "about_text"
    t.string "links_title"
    t.string "stores_title"
    t.string "contact_title"
    t.string "social_title"
    t.string "whatsapp"
    t.string "email"
    t.string "copyright_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "footer_social_links", force: :cascade do |t|
    t.string "platform"
    t.string "url"
    t.boolean "enabled"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "footer_setting_id", null: false
    t.index ["footer_setting_id"], name: "index_footer_social_links_on_footer_setting_id"
  end

  create_table "footer_stores", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.string "zip_code"
    t.string "creci"
    t.string "phone"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "footer_setting_id", null: false
    t.index ["footer_setting_id"], name: "index_footer_stores_on_footer_setting_id"
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "habitation_broker_assignments", force: :cascade do |t|
    t.bigint "habitation_id", null: false
    t.bigint "admin_user_id", null: false
    t.string "role"
    t.string "commission_type"
    t.decimal "commission_value", precision: 10, scale: 2
    t.text "observations"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_habitation_broker_assignments_on_admin_user_id"
    t.index ["habitation_id"], name: "index_habitation_broker_assignments_on_habitation_id"
  end

  create_table "habitation_share_links", force: :cascade do |t|
    t.bigint "habitation_id", null: false
    t.bigint "admin_user_id", null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_clicked_at"
    t.integer "clicks_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_habitation_share_links_on_admin_user_id"
    t.index ["habitation_id", "admin_user_id", "expires_at"], name: "idx_hab_share_links_hab_admin_exp"
    t.index ["habitation_id"], name: "index_habitation_share_links_on_habitation_id"
    t.index ["token"], name: "index_habitation_share_links_on_token", unique: true
  end

  create_table "habitations", force: :cascade do |t|
    t.string "codigo", null: false
    t.string "slug"
    t.string "categoria"
    t.string "status"
    t.string "situacao"
    t.string "tipo"
    t.string "codigo_empreendimento"
    t.string "nome_empreendimento"
    t.string "tipo_endereco"
    t.string "endereco"
    t.string "numero"
    t.string "complemento"
    t.string "bairro"
    t.string "cidade"
    t.string "uf", limit: 2
    t.string "cep", limit: 10
    t.string "pais", default: "Brasil"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.integer "dormitorios_qtd", default: 0
    t.integer "suites_qtd", default: 0
    t.integer "banheiros_qtd", default: 0
    t.integer "vagas_qtd", default: 0
    t.integer "elevadores_qtd", default: 0
    t.decimal "area_privativa_m2", precision: 10, scale: 2
    t.decimal "area_total_m2", precision: 10, scale: 2
    t.decimal "area_terreno_m2", precision: 10, scale: 2
    t.decimal "area_util_m2", precision: 10, scale: 2
    t.bigint "valor_venda_cents"
    t.bigint "valor_locacao_cents"
    t.bigint "valor_condominio_cents"
    t.bigint "valor_iptu_cents"
    t.bigint "valor_por_m2_cents"
    t.jsonb "caracteristicas", default: {}
    t.jsonb "infra_estrutura", default: {}
    t.jsonb "destaque_localizacao", default: {}
    t.jsonb "pictures", default: []
    t.jsonb "videos", default: []
    t.jsonb "plantas", default: []
    t.text "descricao_web"
    t.text "descricao_interna"
    t.string "titulo_anuncio"
    t.text "observacoes"
    t.string "corretor_nome"
    t.string "corretor_telefone"
    t.string "corretor_email"
    t.string "proprietario_codigo"
    t.boolean "exibir_no_site_flag", default: false
    t.boolean "destaque_web_flag", default: false
    t.boolean "lancamento_flag", default: false
    t.boolean "aceita_permuta_flag", default: false
    t.boolean "aceita_financiamento_flag", default: false
    t.boolean "mobiliado_flag", default: false
    t.datetime "data_atualizacao_crm"
    t.datetime "data_cadastro_crm"
    t.string "status_vista"
    t.string "meta_title"
    t.text "meta_description"
    t.string "meta_keywords"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "piscina_flag", default: false
    t.boolean "lavabo_flag", default: false
    t.boolean "varanda_gourmet_flag", default: false
    t.string "bairro_comercial"
    t.string "bloco"
    t.string "lote"
    t.text "imediacoes"
    t.integer "banheiro_social_qtd"
    t.boolean "decorado_flag"
    t.integer "aptos_andar"
    t.integer "aptos_edificio"
    t.boolean "garden_flag"
    t.boolean "quadra_mar_flag"
    t.boolean "sem_mobilia_flag"
    t.integer "valor_venda_anterior_cents"
    t.integer "valor_total_aluguel_cents"
    t.integer "valor_promocional_cents"
    t.string "construtora"
    t.string "proprietario"
    t.string "inscricao_imobiliaria"
    t.text "descricao_empreendimento"
    t.text "caracteristica_unica", default: [], array: true
    t.boolean "terceira_avenida_flag"
    t.boolean "arriba_flag"
    t.boolean "avenida_brasil_flag"
    t.boolean "bairro_fazenda_itajai_flag"
    t.boolean "balneario_picarras_flag"
    t.boolean "barra_flag"
    t.boolean "barra_norte_flag"
    t.boolean "barra_sul_flag"
    t.boolean "cabecudas_flag"
    t.boolean "camboriu_flag"
    t.boolean "centro_flag"
    t.boolean "estaleirinho_flag"
    t.boolean "frente_mar_avenida_atlantica_flag"
    t.boolean "itajai_flag"
    t.boolean "itapema_flag"
    t.boolean "nacoes_flag"
    t.boolean "pioneiros_flag"
    t.boolean "praia_brava_flag"
    t.boolean "praia_dos_amores_flag"
    t.boolean "vista_frente_mar_flag"
    t.boolean "festival_salute_flag"
    t.boolean "exibir_no_site_salute_flag"
    t.string "categoria_grupo"
    t.date "data_entrega"
    t.string "tour_virtual"
    t.jsonb "fotos_empreendimento"
    t.string "codigo_corretor"
    t.string "captador_account_id"
    t.string "agenciador"
    t.string "codigo_dwv"
    t.string "imovel_dwv"
    t.boolean "tem_placa_flag"
    t.jsonb "photo_ids_order", default: []
    t.datetime "last_sync_at"
    t.string "last_sync_status"
    t.text "last_sync_message"
    t.bigint "admin_user_id"
    t.bigint "constructor_id"
    t.string "proprietario_celular"
    t.string "proprietario_telefone_comercial"
    t.string "proprietario_telefone_residencial"
    t.string "proprietario_email"
    t.string "face"
    t.string "perfil_construcao"
    t.string "tipo_vaga"
    t.integer "hidromassagem_qtd"
    t.boolean "exclusivo_flag"
    t.string "ocupacao_status"
    t.string "estado_conservacao"
    t.integer "andar"
    t.integer "ano_construcao"
    t.integer "demi_suites_qtd"
    t.string "numero_box"
    t.string "dimensoes_terreno"
    t.string "topografia"
    t.string "foto_classificacao"
    t.string "podcast_url"
    t.decimal "captador_commission_percentage", precision: 5, scale: 2
    t.decimal "broker_commission_percentage", precision: 5, scale: 2
    t.boolean "salute_rental_management_flag", default: false, null: false
    t.string "key_location"
    t.string "key_location_notes"
    t.bigint "proprietor_id"
    t.boolean "home_corporate_flag", default: false, null: false
    t.integer "home_corporate_position"
    t.integer "valor_aceito_permuta_cents"
    t.boolean "aceita_permuta_veiculo_flag", default: false, null: false
    t.boolean "aceita_permuta_imovel_flag", default: false, null: false
    t.boolean "aceita_permuta_outros_flag", default: false, null: false
    t.string "tipo_veiculo_aceito_permuta"
    t.integer "ano_minimo_veiculo_aceito_permuta"
    t.integer "permuta_valor_cents"
    t.string "permuta_localizacao"
    t.integer "permuta_dormitorios_qtd"
    t.integer "permuta_suites_qtd"
    t.integer "permuta_garagens_qtd"
    t.string "matricula_imovel"
    t.string "zona"
    t.boolean "aceita_doacao_flag", default: false, null: false
    t.text "condicoes_negociacao"
    t.integer "valor_locacao_anterior_cents"
    t.integer "saldo_devedor_cents"
    t.integer "numero_prestacoes"
    t.string "responsavel_reserva"
    t.string "zelador_nome"
    t.string "zelador_telefone"
    t.text "observacoes_visitas"
    t.string "regiao_foco"
    t.string "tipo_fachada"
    t.integer "andares_qtd"
    t.boolean "publicar_imovelweb_2", default: false, null: false
    t.boolean "publicar_netimoveis_2", default: false, null: false
    t.boolean "publicar_lais_ai", default: false, null: false
    t.boolean "publicar_loft", default: false, null: false
    t.boolean "publicar_chaves_na_mao", default: false, null: false
    t.boolean "publicar_casa_mineira", default: false, null: false
    t.boolean "publicar_imovelweb", default: false, null: false
    t.boolean "publicar_viva_real_vrsync", default: false, null: false
    t.string "destaque_chaves_na_mao"
    t.string "periodo_locacao_chaves_na_mao"
    t.string "modelo_casa_mineira"
    t.string "tipo_publicacao_viva_real"
    t.string "divulgar_endereco_viva_real"
    t.string "tipo_publicacao_imovelweb"
    t.string "mostrar_mapa_imovelweb"
    t.string "tipo_publicacao_imovelweb_2"
    t.string "mostrar_mapa_imovelweb_2"
    t.boolean "publicar_zapimoveis", default: false, null: false
    t.index ["aceita_permuta_flag"], name: "index_habitations_on_aceita_permuta_flag"
    t.index ["admin_user_id"], name: "index_habitations_on_admin_user_id"
    t.index ["area_total_m2"], name: "index_habitations_on_area_total_m2"
    t.index ["caracteristicas"], name: "index_habitations_on_caracteristicas", using: :gin
    t.index ["categoria", "status"], name: "idx_habitations_categoria_status"
    t.index ["centro_flag"], name: "index_habitations_on_centro_flag"
    t.index ["cidade", "bairro", "status"], name: "idx_habitations_localizacao_status"
    t.index ["codigo"], name: "index_habitations_on_codigo", unique: true
    t.index ["codigo_dwv"], name: "index_habitations_on_codigo_dwv_unique_when_dwv", unique: true, where: "(((imovel_dwv)::text = 'Sim'::text) AND (codigo_dwv IS NOT NULL) AND ((codigo_dwv)::text <> ''::text))"
    t.index ["codigo_empreendimento"], name: "index_habitations_on_codigo_empreendimento"
    t.index ["constructor_id"], name: "index_habitations_on_constructor_id"
    t.index ["created_at"], name: "index_habitations_on_created_at"
    t.index ["data_atualizacao_crm"], name: "index_habitations_on_data_atualizacao_crm"
    t.index ["destaque_localizacao"], name: "index_habitations_on_destaque_localizacao", using: :gin
    t.index ["destaque_web_flag"], name: "index_habitations_on_destaque_web_flag"
    t.index ["dormitorios_qtd"], name: "index_habitations_on_dormitorios_qtd"
    t.index ["exibir_no_site_flag", "status"], name: "idx_habitations_exibir_status"
    t.index ["frente_mar_avenida_atlantica_flag"], name: "index_habitations_on_frente_mar_avenida_atlantica_flag"
    t.index ["home_corporate_flag", "home_corporate_position"], name: "idx_habitations_home_corporate_order"
    t.index ["home_corporate_flag"], name: "index_habitations_on_home_corporate_flag"
    t.index ["infra_estrutura"], name: "index_habitations_on_infra_estrutura", using: :gin
    t.index ["key_location"], name: "index_habitations_on_key_location"
    t.index ["lancamento_flag"], name: "index_habitations_on_lancamento_flag"
    t.index ["latitude", "longitude"], name: "idx_habitations_geolocation"
    t.index ["lavabo_flag"], name: "index_habitations_on_lavabo_flag"
    t.index ["pictures"], name: "index_habitations_on_pictures", using: :gin
    t.index ["piscina_flag"], name: "index_habitations_on_piscina_flag"
    t.index ["praia_brava_flag"], name: "index_habitations_on_praia_brava_flag"
    t.index ["proprietor_id"], name: "index_habitations_on_proprietor_id"
    t.index ["publicar_casa_mineira"], name: "index_habitations_on_publicar_casa_mineira"
    t.index ["publicar_chaves_na_mao"], name: "index_habitations_on_publicar_chaves_na_mao"
    t.index ["publicar_imovelweb"], name: "index_habitations_on_publicar_imovelweb"
    t.index ["publicar_imovelweb_2"], name: "index_habitations_on_publicar_imovelweb_2"
    t.index ["publicar_lais_ai"], name: "index_habitations_on_publicar_lais_ai"
    t.index ["publicar_loft"], name: "index_habitations_on_publicar_loft"
    t.index ["publicar_netimoveis_2"], name: "index_habitations_on_publicar_netimoveis_2"
    t.index ["publicar_viva_real_vrsync"], name: "index_habitations_on_publicar_viva_real_vrsync"
    t.index ["publicar_zapimoveis"], name: "index_habitations_on_publicar_zapimoveis"
    t.index ["quadra_mar_flag"], name: "index_habitations_on_quadra_mar_flag"
    t.index ["salute_rental_management_flag"], name: "index_habitations_on_salute_rental_management_flag"
    t.index ["slug"], name: "index_habitations_on_slug", unique: true
    t.index ["status", "categoria", "cidade"], name: "idx_habitations_status_categoria_cidade"
    t.index ["updated_at"], name: "index_habitations_on_updated_at"
    t.index ["vagas_qtd"], name: "index_habitations_on_vagas_qtd"
    t.index ["valor_locacao_cents"], name: "index_habitations_on_valor_locacao_cents"
    t.index ["valor_venda_cents", "status"], name: "idx_habitations_venda_status"
    t.index ["valor_venda_cents"], name: "index_habitations_on_valor_venda_cents"
  end

  create_table "home_section_items", force: :cascade do |t|
    t.bigint "home_section_id", null: false
    t.string "title"
    t.text "description"
    t.boolean "active"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["home_section_id"], name: "index_home_section_items_on_home_section_id"
  end

  create_table "home_sections", force: :cascade do |t|
    t.integer "section_type"
    t.string "title"
    t.text "subtitle"
    t.boolean "active"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order_position", default: 0
  end

  create_table "home_settings", force: :cascade do |t|
    t.text "hero_title"
    t.text "hero_subtitle"
    t.text "cta_title"
    t.text "cta_subtitle"
    t.boolean "services_active"
    t.boolean "why_choose_active"
    t.boolean "cta_contact_active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hero_cta_text"
    t.string "hero_cta_link"
    t.decimal "overlay_opacity"
    t.string "overlay_color"
    t.string "hero_button_color"
    t.string "hero_button_text_color"
  end

  create_table "landing_pages", force: :cascade do |t|
    t.string "title"
    t.string "slug"
    t.jsonb "filter_params", default: {}
    t.string "meta_title"
    t.text "meta_description"
    t.text "content"
    t.boolean "active"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "layout_settings", force: :cascade do |t|
    t.string "primary_color"
    t.string "secondary_color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "site_name"
    t.string "accent_color"
  end

  create_table "lead_activities", force: :cascade do |t|
    t.bigint "lead_id", null: false
    t.string "kind"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id"], name: "index_lead_activities_on_lead_id"
  end

  create_table "leads", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.integer "property_id"
    t.string "source_url"
    t.string "lead_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.text "notes"
    t.string "client_name"
    t.string "client_email"
    t.string "client_phone"
    t.string "client_c2s_id"
    t.string "agent_name"
    t.string "agent_email"
    t.string "agent_phone"
    t.string "agent_c2s_id"
    t.string "event_name"
    t.string "origin"
    t.string "product"
    t.jsonb "other_information", default: {}
    t.jsonb "custom_answers", default: []
    t.bigint "distribution_rule_id"
    t.bigint "admin_user_id"
    t.string "share_token"
    t.bigint "shared_by_admin_user_id"
    t.index ["admin_user_id"], name: "index_leads_on_admin_user_id"
    t.index ["client_c2s_id"], name: "index_leads_on_client_c2s_id"
    t.index ["distribution_rule_id"], name: "index_leads_on_distribution_rule_id"
    t.index ["origin"], name: "index_leads_on_origin"
    t.index ["share_token"], name: "index_leads_on_share_token"
    t.index ["shared_by_admin_user_id"], name: "index_leads_on_shared_by_admin_user_id"
  end

  create_table "meta_facebook_pages", force: :cascade do |t|
    t.bigint "user_meta_integration_id", null: false
    t.string "page_id"
    t.string "name"
    t.string "access_token"
    t.boolean "active", default: true
    t.string "category"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["page_id"], name: "index_meta_facebook_pages_on_page_id", unique: true
    t.index ["user_meta_integration_id"], name: "index_meta_facebook_pages_on_user_meta_integration_id"
  end

  create_table "meta_lead_forms", force: :cascade do |t|
    t.bigint "meta_facebook_page_id", null: false
    t.string "form_id"
    t.string "name"
    t.boolean "active", default: true
    t.datetime "facebook_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["form_id"], name: "index_meta_lead_forms_on_form_id", unique: true
    t.index ["meta_facebook_page_id"], name: "index_meta_lead_forms_on_meta_facebook_page_id"
  end

  create_table "portal_integration_events", force: :cascade do |t|
    t.string "portal", null: false
    t.bigint "habitation_id"
    t.string "habitation_code"
    t.string "external_listing_id"
    t.string "event_type", null: false
    t.string "normalized_status"
    t.datetime "received_at", null: false
    t.string "source_ip"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["habitation_id"], name: "index_portal_integration_events_on_habitation_id"
    t.index ["portal", "external_listing_id"], name: "idx_on_portal_external_listing_id_a9202d155f"
    t.index ["portal", "habitation_code"], name: "index_portal_integration_events_on_portal_and_habitation_code"
    t.index ["portal", "received_at"], name: "index_portal_integration_events_on_portal_and_received_at"
  end

  create_table "portal_integrations", force: :cascade do |t|
    t.string "portal", null: false
    t.boolean "enabled", default: false, null: false
    t.string "allowed_statuses", default: [], null: false, array: true
    t.string "allowed_business_types", default: ["venda", "aluguel"], null: false, array: true
    t.boolean "require_exibir_no_site", default: true, null: false
    t.string "feed_token", null: false
    t.string "account_id"
    t.string "publisher_id"
    t.string "webhook_secret"
    t.string "operational_status", default: "idle", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "last_feed_at"
    t.datetime "last_webhook_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_portal_integrations_on_enabled"
    t.index ["feed_token"], name: "index_portal_integrations_on_feed_token", unique: true
    t.index ["portal"], name: "index_portal_integrations_on_portal", unique: true
  end

  create_table "portal_listing_states", force: :cascade do |t|
    t.string "portal", null: false
    t.bigint "habitation_id"
    t.string "habitation_code"
    t.string "external_listing_id"
    t.string "last_event_type", null: false
    t.string "last_status"
    t.datetime "last_received_at", null: false
    t.jsonb "last_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["habitation_id"], name: "index_portal_listing_states_on_habitation_id"
    t.index ["portal", "external_listing_id"], name: "idx_portal_listing_states_portal_external", unique: true, where: "(external_listing_id IS NOT NULL)"
    t.index ["portal", "habitation_code"], name: "idx_portal_listing_states_portal_code", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.string "name"
    t.jsonb "permissions"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "property_pages", force: :cascade do |t|
    t.string "title", null: false
    t.string "meta_title"
    t.text "meta_description"
    t.string "slug", null: false
    t.jsonb "filter_params", default: {}
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_property_pages_on_slug", unique: true
  end

  create_table "proprietors", force: :cascade do |t|
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.string "vista_code"
    t.string "cpf_cnpj"
    t.string "rg_ie"
    t.string "issuing_authority"
    t.date "birth_date"
    t.string "email"
    t.string "phone_primary"
    t.string "mobile_phone"
    t.string "residential_phone"
    t.string "business_phone"
    t.string "phone_extension"
    t.string "profession"
    t.string "marital_status"
    t.string "marriage_regime"
    t.string "nationality"
    t.string "capture_vehicle"
    t.date "registered_at"
    t.text "notes"
    t.boolean "is_client", default: false, null: false
    t.string "address_type"
    t.string "street"
    t.string "number"
    t.string "complement"
    t.string "block"
    t.string "uf", limit: 2
    t.string "cep", limit: 10
    t.string "neighborhood"
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "spouse_name"
    t.string "spouse_email"
    t.string "spouse_phone"
    t.string "spouse_cpf_cnpj"
    t.index ["cpf_cnpj"], name: "index_proprietors_on_cpf_cnpj"
    t.index ["email"], name: "index_proprietors_on_email"
    t.index ["name"], name: "index_proprietors_on_name"
    t.index ["spouse_cpf_cnpj"], name: "index_proprietors_on_spouse_cpf_cnpj"
    t.index ["spouse_email"], name: "index_proprietors_on_spouse_email"
    t.index ["spouse_name"], name: "index_proprietors_on_spouse_name"
    t.index ["vista_code"], name: "index_proprietors_on_vista_code"
  end

  create_table "seo_settings", force: :cascade do |t|
    t.string "page_name"
    t.string "meta_title"
    t.text "meta_description"
    t.text "meta_keywords"
    t.string "og_image"
    t.string "canonical_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "settings", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key_unique", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "store_shifts", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "admin_user_id", null: false
    t.integer "day_of_week", null: false
    t.time "start_time", null: false
    t.time "end_time", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id", "day_of_week", "active"], name: "idx_store_shifts_agent_day_active"
    t.index ["admin_user_id"], name: "index_store_shifts_on_admin_user_id"
    t.index ["store_id", "day_of_week"], name: "index_store_shifts_on_store_id_and_day_of_week"
    t.index ["store_id"], name: "index_store_shifts_on_store_id"
  end

# Could not dump table "stores" because of following StandardError
#   Unknown type 'geography(Point,4326)' for column 'location'

  create_table "user_meta_integrations", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.string "access_token"
    t.string "facebook_user_id"
    t.string "name"
    t.string "email"
    t.datetime "token_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sync_status"
    t.integer "sync_progress"
    t.datetime "last_synced_at"
    t.string "sync_message"
    t.index ["admin_user_id"], name: "index_user_meta_integrations_on_admin_user_id"
  end

  create_table "webhook_settings", force: :cascade do |t|
    t.string "webhook_url"
    t.boolean "enabled", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "whatsapp_webhook_url"
    t.boolean "lead_capture_enabled"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_users", "admin_users", column: "manager_id"
  add_foreign_key "admin_users", "profiles"
  add_foreign_key "admin_users", "stores", column: "default_store_id"
  add_foreign_key "distribution_rule_agents", "admin_users"
  add_foreign_key "distribution_rule_agents", "distribution_rules"
  add_foreign_key "footer_links", "footer_settings"
  add_foreign_key "footer_social_links", "footer_settings"
  add_foreign_key "footer_stores", "footer_settings"
  add_foreign_key "habitation_broker_assignments", "admin_users"
  add_foreign_key "habitation_broker_assignments", "habitations"
  add_foreign_key "habitation_share_links", "admin_users"
  add_foreign_key "habitation_share_links", "habitations"
  add_foreign_key "habitations", "admin_users"
  add_foreign_key "habitations", "constructors"
  add_foreign_key "habitations", "proprietors"
  add_foreign_key "home_section_items", "home_sections"
  add_foreign_key "lead_activities", "leads"
  add_foreign_key "leads", "admin_users"
  add_foreign_key "leads", "admin_users", column: "shared_by_admin_user_id"
  add_foreign_key "leads", "distribution_rules"
  add_foreign_key "meta_facebook_pages", "user_meta_integrations"
  add_foreign_key "meta_lead_forms", "meta_facebook_pages"
  add_foreign_key "portal_integration_events", "habitations"
  add_foreign_key "portal_listing_states", "habitations"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "store_shifts", "admin_users"
  add_foreign_key "store_shifts", "stores"
  add_foreign_key "stores", "admin_users", column: "director_admin_user_id"
  add_foreign_key "stores", "footer_stores"
  add_foreign_key "user_meta_integrations", "admin_users"
end
