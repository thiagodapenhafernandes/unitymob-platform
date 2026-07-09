module Habitation::SearchScopes
  extend ActiveSupport::Concern

  UNIQUE_FEATURES_ARRAY_SQL = "CASE " \
                              "WHEN pg_typeof(habitations.caracteristica_unica)::text = 'text[]' " \
                              "THEN COALESCE(habitations.caracteristica_unica::text[], ARRAY[]::text[]) " \
                              "ELSE string_to_array(COALESCE(habitations.caracteristica_unica::text, ''), ',') " \
                              "END".freeze
  LOCATION_CITY_SQL = "COALESCE(NULLIF(TRIM(addresses.cidade), ''), NULLIF(TRIM(habitations.cidade), ''))".freeze
  LOCATION_NEIGHBORHOOD_SQL = "COALESCE(NULLIF(TRIM(addresses.bairro), ''), NULLIF(TRIM(habitations.bairro), ''))".freeze
  LOCATION_CITY_NORM_SQL = "LOWER(unaccent(#{LOCATION_CITY_SQL}))".freeze
  LOCATION_NEIGHBORHOOD_NORM_SQL = "LOWER(unaccent(#{LOCATION_NEIGHBORHOOD_SQL}))".freeze
  LOCATION_LABEL_NORM_SQL = "LOWER(unaccent(CONCAT_WS(' - ', #{LOCATION_NEIGHBORHOOD_SQL}, #{LOCATION_CITY_SQL})))".freeze
  
  included do
    # Scopes básicos de visibilidade
    # IMPORTANTE: Apenas imóveis com status válido para exibição pública
    scope :publicly_listable, -> {
      where(exibir_no_site_flag: true)
        .where(status: Habitation::PUBLIC_STATUSES)
    }
    scope :public_filterable_locations, -> {
      publicly_listable
        .without_developments
        .where("habitations.valor_venda_cents > 0 OR habitations.valor_locacao_cents > 0")
    }
    scope :public_property_listable, -> {
      publicly_listable
        .without_developments
        .with_public_property_photos
        .with_public_listing_price
    }
    scope :active, -> {
      publicly_listable
        .with_photos
        .where(
          "(habitations.tipo = 'Empreendimento' AND EXISTS (" \
          "SELECT 1 FROM habitations units " \
          "WHERE units.codigo_empreendimento = habitations.codigo " \
          "AND units.tenant_id = habitations.tenant_id " \
          "AND units.exibir_no_site_flag = TRUE " \
          "AND units.status IN (?) " \
          "AND (units.valor_venda_cents > 0 OR units.valor_locacao_cents > 0) " \
          "AND (" \
          "  (jsonb_typeof(units.pictures) = 'array' AND jsonb_array_length(units.pictures) > 0) OR " \
          "  (jsonb_typeof(units.fotos_empreendimento) = 'array' AND jsonb_array_length(units.fotos_empreendimento) > 0) OR " \
          "  EXISTS (SELECT 1 FROM active_storage_attachments WHERE active_storage_attachments.record_id = units.id AND active_storage_attachments.record_type = 'Habitation')" \
          ")" \
          ")) OR " \
          "(COALESCE(habitations.tipo, '') <> 'Empreendimento' AND (habitations.valor_venda_cents > 0 OR habitations.valor_locacao_cents > 0))",
          Habitation::PUBLIC_STATUSES
        )
    }
    scope :without_developments, -> {
      where(
        "COALESCE(habitations.tipo, '') <> 'Empreendimento' " \
        "AND COALESCE(habitations.imovel_dwv, '') <> 'Sim'"
      )
    }
    scope :featured, -> { where(destaque_web_flag: true) }
    scope :home_corporate, -> {
      where(home_corporate_flag: true)
        .order(Arel.sql("COALESCE(home_corporate_position, 9999) ASC"), updated_at: :desc)
    }
    scope :lancamento, -> {
      where(
        "lancamento_flag = true OR EXISTS (" \
        "SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature " \
        "WHERE unaccent(feature) ILIKE unaccent('%lançamento%')" \
        ")"
      )
    }
    scope :na_planta, -> {
      where(
        "EXISTS (" \
        "SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature " \
        "WHERE unaccent(feature) ILIKE unaccent('%planta%')" \
        ")"
      )
    }
    scope :pronto, -> {
      where(
        "EXISTS (" \
        "SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature " \
        "WHERE unaccent(feature) ILIKE unaccent('%pronto%')" \
        ")"
      )
    }
    scope :em_construcao, -> {
      where(
        "EXISTS (" \
        "SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature " \
        "WHERE unaccent(feature) ILIKE unaccent('%construção%')" \
        ")"
      )
    }
    
    # Scope para imóveis com fotos públicas. Unidades vinculadas contam fotos
    # próprias e fotos do empreendimento para refletir a galeria pública.
    scope :with_photos, -> { 
      where(
        "((COALESCE(habitations.tipo, '') = 'Empreendimento' AND (" \
        "  (jsonb_typeof(pictures) = 'array' AND jsonb_array_length(pictures) > 0) OR " \
        "  (jsonb_typeof(fotos_empreendimento) = 'array' AND jsonb_array_length(fotos_empreendimento) > 0) OR " \
        "  EXISTS (SELECT 1 FROM active_storage_attachments WHERE active_storage_attachments.record_id = habitations.id AND active_storage_attachments.record_type = 'Habitation' AND active_storage_attachments.name = 'photos')" \
        ")) OR (COALESCE(habitations.tipo, '') <> 'Empreendimento' AND (" \
        "  (jsonb_typeof(pictures) = 'array' AND jsonb_array_length(pictures) > 0) OR " \
        "  (habitations.use_development_photos_flag IS TRUE AND NULLIF(BTRIM(habitations.codigo_empreendimento), '') IS NOT NULL AND jsonb_typeof(fotos_empreendimento) = 'array' AND jsonb_array_length(fotos_empreendimento) > 0) OR " \
        "  (habitations.use_development_photos_flag IS TRUE AND EXISTS (" \
        "    SELECT 1 FROM habitations developments " \
        "    WHERE developments.codigo = habitations.codigo_empreendimento " \
        "      AND developments.tenant_id = habitations.tenant_id " \
        "      AND COALESCE(developments.tipo, '') = 'Empreendimento' " \
        "      AND (" \
        "        (jsonb_typeof(developments.pictures) = 'array' AND jsonb_array_length(developments.pictures) > 0) OR " \
        "        (jsonb_typeof(developments.fotos_empreendimento) = 'array' AND jsonb_array_length(developments.fotos_empreendimento) > 0) OR " \
        "        EXISTS (SELECT 1 FROM active_storage_attachments dev_attachments WHERE dev_attachments.record_id = developments.id AND dev_attachments.record_type = 'Habitation' AND dev_attachments.name = 'photos')" \
        "      )" \
        "  )) OR " \
        "  EXISTS (SELECT 1 FROM active_storage_attachments WHERE active_storage_attachments.record_id = habitations.id AND active_storage_attachments.record_type = 'Habitation' AND active_storage_attachments.name = 'photos')" \
        ")))"
      ) 
    }
    scope :with_public_property_photos, -> {
      where(
        "(" \
        "  (jsonb_typeof(pictures) = 'array' AND jsonb_array_length(pictures) > 0) OR " \
        "  (habitations.use_development_photos_flag IS TRUE AND NULLIF(BTRIM(habitations.codigo_empreendimento), '') IS NOT NULL AND jsonb_typeof(fotos_empreendimento) = 'array' AND jsonb_array_length(fotos_empreendimento) > 0) OR " \
        "  (habitations.use_development_photos_flag IS TRUE AND EXISTS (" \
        "    SELECT 1 FROM habitations developments " \
        "    WHERE developments.codigo = habitations.codigo_empreendimento " \
        "      AND developments.tenant_id = habitations.tenant_id " \
        "      AND COALESCE(developments.tipo, '') = 'Empreendimento' " \
        "      AND (" \
        "        (jsonb_typeof(developments.pictures) = 'array' AND jsonb_array_length(developments.pictures) > 0) OR " \
        "        (jsonb_typeof(developments.fotos_empreendimento) = 'array' AND jsonb_array_length(developments.fotos_empreendimento) > 0) OR " \
        "        EXISTS (SELECT 1 FROM active_storage_attachments dev_attachments WHERE dev_attachments.record_id = developments.id AND dev_attachments.record_type = 'Habitation' AND dev_attachments.name = 'photos')" \
        "      )" \
        "  )) OR " \
        "  EXISTS (SELECT 1 FROM active_storage_attachments WHERE active_storage_attachments.record_id = habitations.id AND active_storage_attachments.record_type = 'Habitation' AND active_storage_attachments.name = 'photos')" \
        ")"
      )
    }
    
    # Scope para imóveis com preço (venda ou locação)
    scope :with_price, -> { where("valor_venda_cents > 0 OR valor_locacao_cents > 0") }
    scope :with_public_listing_price, -> { where("valor_venda_cents > 0 OR valor_locacao_cents > 0") }
    
    # Scopes por tipo de transação (baseado em preço)
    scope :for_sale, -> { where("valor_venda_cents > 0") }
    scope :for_rent, -> { where("valor_locacao_cents > 0") }
    
    # Scopes por categoria (com unaccent)
    scope :by_category, ->(category) { 
      if category.is_a?(Array)
        clean = category.reject(&:blank?).map { |item| item.to_s.strip }
        if clean.any?
          relation = none
          regular_categories = clean

          if clean.any? { |item| item.casecmp("Empreendimento").zero? }
            relation = relation.or(where(tipo: "Empreendimento"))
            regular_categories = regular_categories.reject { |item| item.casecmp("Empreendimento").zero? }
          end

          if clean.any? { |item| item.casecmp("Garden").zero? }
            relation = relation.or(garden)
            regular_categories = regular_categories.reject { |item| item.casecmp("Garden").zero? }
          end

          if clean.any? { |item| item.casecmp("Diferenciado").zero? }
            relation = relation.or(diferenciado)
            regular_categories = regular_categories.reject { |item| item.casecmp("Diferenciado").zero? }
          end

          if regular_categories.any?
            relation.or(where("unaccent(categoria) IN (SELECT unaccent(n) FROM unnest(ARRAY[?]) AS n)", regular_categories))
          else
            relation
          end
        else
          all
        end
      elsif category.present?
        if category.to_s.casecmp("Empreendimento").zero?
          where(tipo: "Empreendimento")
        elsif category.to_s.casecmp("Garden").zero?
          garden
        elsif category.to_s.casecmp("Diferenciado").zero?
          diferenciado
        else
          where("unaccent(categoria) ILIKE unaccent(?)", category)
        end
      else
        all
      end
    }
    scope :apartamentos, -> { where("unaccent(categoria) ILIKE unaccent(?)", "%apartamento%") }
    scope :casas, -> { where("unaccent(categoria) ILIKE unaccent(?)", "%casa%") }
    scope :terrenos, -> { where("unaccent(categoria) ILIKE unaccent(?)", "%terreno%") }
    scope :comerciais, -> { where("unaccent(categoria) ILIKE unaccent(?)", "%comercial%") }
    
    # Scopes por localização (com unaccent e busca flexível)
    scope :by_city, ->(city) { 
      if city.is_a?(Array)
        clean = normalize_location_values(city)
        if clean.any?
          left_outer_joins(:address).where("#{LOCATION_CITY_NORM_SQL} IN (?)", clean)
        else
          all
        end
      elsif city.present?
        left_outer_joins(:address).where("#{LOCATION_CITY_NORM_SQL} ILIKE ?", "%#{normalize_location_value(city)}%")
      else
        all
      end
    }
    scope :by_neighborhood, ->(neighborhood) { 
      if neighborhood.is_a?(Array)
        neighborhood_clean = normalize_location_values(neighborhood)
        if neighborhood_clean.any?
          left_outer_joins(:address).where("#{LOCATION_NEIGHBORHOOD_NORM_SQL} IN (?) OR #{LOCATION_LABEL_NORM_SQL} IN (?)", neighborhood_clean, neighborhood_clean)
        else
          all
        end
      elsif neighborhood.present?
        normalized = normalize_location_value(neighborhood)
        left_outer_joins(:address).where("#{LOCATION_NEIGHBORHOOD_NORM_SQL} ILIKE ? OR #{LOCATION_LABEL_NORM_SQL} ILIKE ?", "%#{normalized}%", "%#{normalized}%")
      else
        all
      end
    }
    scope :by_public_locations, ->(locations) {
      normalized_locations = normalize_location_values(locations)
      if normalized_locations.any?
        left_outer_joins(:address).where(
          "#{LOCATION_CITY_NORM_SQL} IN (:locations) OR " \
          "#{LOCATION_NEIGHBORHOOD_NORM_SQL} IN (:locations) OR " \
          "#{LOCATION_LABEL_NORM_SQL} IN (:locations)",
          locations: normalized_locations
        )
      else
        all
      end
    }
    scope :by_state, ->(state) { left_outer_joins(:address).where("COALESCE(addresses.uf, habitations.uf) = ?", state) if state.present? }
    
    # Scopes por características
    scope :with_min_bedrooms, ->(count) { where("dormitorios_qtd >= ?", count) if count.present? }
    scope :with_min_suites, ->(count) { where("suites_qtd >= ?", count) if count.present? }
    scope :with_min_bathrooms, ->(count) { where("banheiros_qtd >= ?", count) if count.present? }
    scope :with_min_parking, ->(count) { where("vagas_qtd >= ?", count) if count.present? }
    
    # Scopes por área
    scope :with_min_area, ->(area) { where("area_total_m2 >= ?", area) if area.present? }
    scope :with_max_area, ->(area) { where("area_total_m2 <= ?", area) if area.present? }
    scope :by_area_range, ->(min, max) {
      query = all
      query = query.where("area_total_m2 >= ?", min) if min.present?
      query = query.where("area_total_m2 <= ?", max) if max.present?
      query
    }
    
    # Scopes por preço
    scope :with_min_price, ->(price) {
      return unless price.present?
      # Remove pontos de formatação antes de converter
      price_cents = price.to_s.gsub(/[^\d]/, '').to_i * 100
      where("valor_venda_cents >= ? OR valor_locacao_cents >= ?", price_cents, price_cents)
    }
    scope :with_max_price, ->(price) {
      return unless price.present?
      # Remove pontos de formatação antes de converter
      price_cents = price.to_s.gsub(/[^\d]/, '').to_i * 100
      where("valor_venda_cents <= ? OR valor_locacao_cents <= ?", price_cents, price_cents)
    }
    scope :by_price_range, ->(min, max) {
      query = all
      if min.present?
        # Remove pontos de formatação antes de converter
        min_cents = min.to_s.gsub(/[^\d]/, '').to_i * 100
        query = query.where("valor_venda_cents >= ? OR valor_locacao_cents >= ?", min_cents, min_cents)
      end
      if max.present?
        # Remove pontos de formatação antes de converter
        max_cents = max.to_s.gsub(/[^\d]/, '').to_i * 100
        query = query.where("valor_venda_cents <= ? OR valor_locacao_cents <= ?", max_cents, max_cents)
      end
      query
    }
    
    # Scopes por flags
    scope :mobiliado, -> { where("mobiliado_flag = true OR caracteristicas ? 'mobiliado'") }
    scope :aceita_permuta, -> { where(aceita_permuta_flag: true) }
    scope :aceita_financiamento, -> { where(aceita_financiamento_flag: true) }
    
    # Scope para busca de texto robusta (com unaccent)
    scope :search_text, ->(query) {
      if query.present?
        sanitized = query.strip
        left_outer_joins(:address).where(
          "unaccent(titulo_anuncio) ILIKE unaccent(:q) OR " \
          "unaccent(descricao_web) ILIKE unaccent(:q) OR " \
          "unaccent(COALESCE(addresses.logradouro, habitations.endereco)) ILIKE unaccent(:q) OR " \
          "unaccent(COALESCE(addresses.bairro, habitations.bairro)) ILIKE unaccent(:q) OR " \
          "unaccent(COALESCE(addresses.cidade, habitations.cidade)) ILIKE unaccent(:q) OR " \
          "unaccent(nome_empreendimento) ILIKE unaccent(:q) OR " \
          "EXISTS (" \
          "SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature " \
          "WHERE unaccent(feature) ILIKE unaccent(:q)" \
          ") OR " \
          "codigo ILIKE :q",
          q: "%#{sanitized}%"
        )
      end
    }

    scope :admin_search_text, ->(query) {
      sanitized = query.to_s.squish
      if sanitized.present?
        phrase = "%#{sanitize_sql_like(sanitized)}%"
        terms = sanitized
          .split(/\s+/)
          .map { |term| term.strip }
          .reject(&:blank?)
          .uniq
          .first(6)

        searchable_text_sql = <<~SQL.squish
          CONCAT_WS(' ',
            habitations.codigo,
            habitations.codigo_empreendimento,
            habitations.titulo_anuncio,
            habitations.descricao_web,
            habitations.nome_empreendimento,
            COALESCE(NULLIF(TRIM(addresses.tipo_endereco), ''), NULLIF(TRIM(habitations.tipo_endereco), '')),
            COALESCE(NULLIF(TRIM(addresses.logradouro), ''), NULLIF(TRIM(habitations.endereco), '')),
            COALESCE(NULLIF(TRIM(addresses.numero), ''), NULLIF(TRIM(habitations.numero), '')),
            COALESCE(NULLIF(TRIM(addresses.cep), ''), NULLIF(TRIM(habitations.cep), '')),
            COALESCE(NULLIF(TRIM(addresses.bairro), ''), NULLIF(TRIM(habitations.bairro), '')),
            COALESCE(NULLIF(TRIM(addresses.bairro_comercial), ''), NULLIF(TRIM(habitations.bairro_comercial), '')),
            COALESCE(NULLIF(TRIM(addresses.cidade), ''), NULLIF(TRIM(habitations.cidade), '')),
            COALESCE((
              SELECT developments.nome_empreendimento
              FROM habitations developments
              WHERE developments.codigo = habitations.codigo_empreendimento
                AND developments.tenant_id = habitations.tenant_id
              LIMIT 1
            ), '')
          )
        SQL

        bindings = { admin_search_phrase: phrase }
        term_conditions = terms.each_with_index.map do |term, index|
          key = :"admin_search_term_#{index}"
          bindings[key] = "%#{sanitize_sql_like(term)}%"
          "unaccent(#{searchable_text_sql}) ILIKE unaccent(:#{key})"
        end

        token_condition = term_conditions.any? ? " OR (#{term_conditions.join(' AND ')})" : ""

        left_outer_joins(:address).where(
          "unaccent(#{searchable_text_sql}) ILIKE unaccent(:admin_search_phrase)#{token_condition}",
          bindings
        )
      else
        all
      end
    }
    
    # Busca em características JSONB (frente mar, quadra mar, varanda, etc)
    scope :search_characteristics, ->(query) {
      if query.present?
        sanitized = query.strip.downcase
        where(
          "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE unaccent(?))",
          "%#{sanitized}%"
        )
      end
    }
    
    # Busca em infraestrutura JSONB
    scope :search_infrastructure, ->(query) {
      if query.present?
        sanitized = query.strip.downcase
        where(
          "jsonb_typeof(infra_estrutura) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(infra_estrutura) WHERE unaccent(lower(value)) ILIKE unaccent(?))",
          "%#{sanitized}%"
        )
      end
    }
    
    # Características específicas comuns
    # Frente Mar = Avenida beira-mar (primeira linha)
    scope :frente_mar, lambda {
      where(
        "frente_mar_avenida_atlantica_flag = true OR " \
        "vista_frente_mar_flag = true OR " \
        "unaccent(descricao_web) ILIKE unaccent('%frente%mar%')"
      )
    }
    
    # Vista Mar = Vista para o mar (qualquer posição)
    scope :vista_mar, lambda {
      where("caracteristicas ? 'vista_mar' OR vista_mar_flag = true")
    }

    # Quadra Mar
    scope :quadra_mar, lambda {
      where("quadra_mar_flag = true OR caracteristicas ? 'quadra_mar'")
    }

    # Sacada
    scope :sacada, lambda {
      where("caracteristicas ? 'sacada' OR varanda_gourmet_flag = true")
    }

    # Decorado
    scope :decorado, lambda {
      where("decorado_flag = true OR caracteristicas ? 'decorado'")
    }

    # Garden
    scope :garden, lambda {
      where(garden_flag: true)
    }

    scope :diferenciado, lambda {
      where(
        "unaccent(categoria) ILIKE unaccent('Diferenciado') OR " \
        "caracteristicas ? 'Diferenciado' OR " \
        "EXISTS (" \
        "SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature " \
        "WHERE unaccent(feature) ILIKE unaccent('Diferenciado')" \
        ")"
      )
    }

    # Festival Salute
    scope :festival_salute, lambda {
      where(festival_salute_flag: true)
    }

    # Compatibilidade para filtros antigos que usavam "Exibir no Site Salute".
    scope :exibir_site_salute, lambda {
      where(exibir_no_site_flag: true)
    }

    # Oportunidade (Preço Reduzido)
    scope :opportunity, lambda {
      where(
        "valor_venda_anterior_cents > valor_venda_cents AND valor_venda_cents > 0"
      )
    }
    
    scope :quadra_mar, -> { 
      where("quadra_mar_flag = true OR caracteristicas ? 'quadramar'")
    }
    
    scope :varanda, -> { 
      where("caracteristicas->> 'varanda' = 'true' OR " \
            "varanda_gourmet_flag = true OR " \
            "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%varanda%')")
    }
    
    # Outras características via JSONB
    scope :churrasqueira, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%churrasqueira%') OR " \
            "(jsonb_typeof(infra_estrutura) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(infra_estrutura) WHERE unaccent(lower(value)) ILIKE '%churrasqueira%'))")
    }

    scope :cozinha_gourmet_churrasqueira, -> {
      where(
        "(" \
        "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) kv WHERE unaccent(lower(kv.key)) ILIKE unaccent('%cozinha%churrasqueir%') OR unaccent(lower(kv.value)) ILIKE unaccent('%cozinha%churrasqueir%')) OR " \
        "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) kv WHERE unaccent(lower(kv.key)) ILIKE unaccent('%cozinha%gourmet%churrasqueir%') OR unaccent(lower(kv.value)) ILIKE unaccent('%cozinha%gourmet%churrasqueir%')) OR " \
        "((" \
        "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) kv WHERE unaccent(lower(kv.key)) ILIKE unaccent('%cozinha%gourmet%') OR unaccent(lower(kv.value)) ILIKE unaccent('%cozinha%gourmet%') OR unaccent(lower(kv.key)) ILIKE unaccent('%gourmet%') OR unaccent(lower(kv.value)) ILIKE unaccent('%gourmet%'))" \
        ") AND (" \
        "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) kv WHERE unaccent(lower(kv.key)) ILIKE unaccent('%churrasqueir%') OR unaccent(lower(kv.value)) ILIKE unaccent('%churrasqueir%')) OR " \
        "(jsonb_typeof(infra_estrutura) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(infra_estrutura) value WHERE unaccent(lower(value)) ILIKE unaccent('%churrasqueir%')))" \
        ")) OR " \
        "unaccent(lower(COALESCE(descricao_web, ''))) ILIKE unaccent('%cozinha%churrasqueir%') OR " \
        "unaccent(lower(COALESCE(descricao_web, ''))) ILIKE unaccent('%gourmet%churrasqueir%')" \
        ")"
      )
    }
    
    scope :sacada, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%sacada%')")
    }
    
    scope :decorado, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%decorado%')")
    }
    
    scope :vista_mar, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%vista%mar%')")
    }
    
    scope :closet, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%closet%')")
    }
    
    scope :semi_mobiliado, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%semi%mobiliado%')")
    }
    
    scope :lavabo, -> {
      where("lavabo_flag = true OR " \
            "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%lavabo%')")
    }
    
    scope :lavanderia, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%lavanderia%')")
    }

    scope :sol_manha, -> {
      where(
        "unaccent(lower(COALESCE(face, ''))) IN ('leste', 'nordeste', 'sudeste') OR " \
        "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) kv WHERE unaccent(lower(kv.key)) ILIKE unaccent('%sol%manha%') OR unaccent(lower(kv.value)) ILIKE unaccent('%sol%manha%') OR unaccent(lower(kv.key)) ILIKE unaccent('%sol%matinal%') OR unaccent(lower(kv.value)) ILIKE unaccent('%sol%matinal%')) OR " \
        "unaccent(lower(COALESCE(descricao_web, ''))) ILIKE unaccent('%sol%manha%')"
      )
    }

    scope :sol_tarde, -> {
      where(
        "unaccent(lower(COALESCE(face, ''))) IN ('oeste', 'noroeste', 'sudoeste') OR " \
        "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) kv WHERE unaccent(lower(kv.key)) ILIKE unaccent('%sol%tarde%') OR unaccent(lower(kv.value)) ILIKE unaccent('%sol%tarde%')) OR " \
        "unaccent(lower(COALESCE(descricao_web, ''))) ILIKE unaccent('%sol%tarde%')"
      )
    }

    scope :sol_dia_todo, -> {
      where(
        "unaccent(lower(COALESCE(face, ''))) = 'norte' OR " \
        "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) kv WHERE unaccent(lower(kv.key)) ILIKE unaccent('%sol%dia%todo%') OR unaccent(lower(kv.value)) ILIKE unaccent('%sol%dia%todo%') OR unaccent(lower(kv.key)) ILIKE unaccent('%sol%manha%tarde%') OR unaccent(lower(kv.value)) ILIKE unaccent('%sol%manha%tarde%')) OR " \
        "unaccent(lower(COALESCE(descricao_web, ''))) ILIKE unaccent('%sol%dia%todo%') OR " \
        "unaccent(lower(COALESCE(descricao_web, ''))) ILIKE unaccent('%sol%manha%tarde%')"
      )
    }

    scope :dependencia_empregada, -> {
      where(
        "EXISTS (" \
        "SELECT 1 FROM jsonb_each_text(caracteristicas) kv " \
        "WHERE unaccent(lower(kv.key)) ILIKE unaccent('%depend%empreg%') " \
        "OR unaccent(lower(kv.value)) ILIKE unaccent('%depend%empreg%') " \
        "OR unaccent(lower(kv.key)) ILIKE unaccent('%dep%empreg%') " \
        "OR unaccent(lower(kv.value)) ILIKE unaccent('%dep%empreg%') " \
        "OR unaccent(lower(kv.key)) ILIKE unaccent('%quarto%empreg%') " \
        "OR unaccent(lower(kv.value)) ILIKE unaccent('%quarto%empreg%')" \
        ")"
      )
    }
    
    scope :hidromassagem, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%hidromassagem%') OR " \
            "(jsonb_typeof(infra_estrutura) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(infra_estrutura) WHERE unaccent(lower(value)) ILIKE '%hidromassagem%'))")
    }
    
    scope :piscina, -> {
      where("piscina_flag = true OR " \
            "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%piscina%') OR " \
            "(jsonb_typeof(infra_estrutura) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(infra_estrutura) WHERE unaccent(lower(value)) ILIKE '%piscina%'))")
    }
    
    scope :sala_estar, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%sala%estar%')")
    }
    
    scope :sala_jantar, -> {
      where("EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE '%sala%jantar%')")
    }
    
    # Scopes de ordenação
    scope :newest_first, -> { order(data_atualizacao_crm: :desc, created_at: :desc) }
    scope :oldest_first, -> { order(data_atualizacao_crm: :asc, created_at: :asc) }
    scope :price_asc, -> { order(Arel.sql(public_price_sort_sql("ASC"))) }
    scope :price_desc, -> { order(Arel.sql(public_price_sort_sql("DESC"))) }
    scope :area_asc, -> { order(area_total_m2: :asc) }
    scope :area_desc, -> { order(area_total_m2: :desc) }
    
    # Scope para empreendimentos
    scope :empreendimentos, -> { where(tipo: 'Empreendimento') }

    # Empreendimentos publicos com foto e pelo menos 1 unidade disponivel
    scope :empreendimentos_publicos, -> {
      empreendimentos
        .where(exibir_no_site_flag: true)
        .with_development_images
        .with_available_units
    }

    scope :with_development_images, -> {
      where(
        "(jsonb_typeof(fotos_empreendimento) = 'array' AND jsonb_array_length(fotos_empreendimento) > 0) OR " \
        "(jsonb_typeof(pictures) = 'array' AND jsonb_array_length(pictures) > 0)"
      )
    }

    scope :with_available_units, -> {
      where(
        "EXISTS (" \
        "SELECT 1 FROM habitations units " \
        "WHERE units.codigo_empreendimento = habitations.codigo " \
        "AND units.tenant_id = habitations.tenant_id " \
        "AND units.exibir_no_site_flag = TRUE " \
        "AND units.status IN (?) " \
        "AND (units.valor_venda_cents > 0 OR units.valor_locacao_cents > 0) " \
        "AND (" \
        "  (jsonb_typeof(units.pictures) = 'array' AND jsonb_array_length(units.pictures) > 0) OR " \
        "  (jsonb_typeof(units.fotos_empreendimento) = 'array' AND jsonb_array_length(units.fotos_empreendimento) > 0) OR " \
        "  EXISTS (SELECT 1 FROM active_storage_attachments WHERE active_storage_attachments.record_id = units.id AND active_storage_attachments.record_type = 'Habitation')" \
        ")" \
        ")",
        Habitation::PUBLIC_STATUSES
      )
    }
    scope :unidades, -> { where.not(codigo_empreendimento: nil) }
    scope :imoveis_individuais, -> { where(codigo_empreendimento: nil, tipo: 'Unitário').or(where(tipo: nil)) }
  end
  
  class_methods do
    def normalize_location_value(value)
      I18n.transliterate(value.to_s.strip).downcase
    end

    def normalize_location_values(values)
      Array(values).map { |value| normalize_location_value(value) }.reject(&:blank?).uniq
    end

    def public_location_options
      rows = public_filterable_locations
        .left_outer_joins(:address)
        .distinct
        .pluck(Arel.sql("#{LOCATION_CITY_SQL} AS cidade_nome, #{LOCATION_NEIGHBORHOOD_SQL} AS bairro_nome"))

      city_labels = canonical_location_labels(rows.map(&:first))
      neighborhood_labels = canonical_location_labels(rows.filter_map do |city, neighborhood|
        next if city.blank? || neighborhood.blank?

        "#{neighborhood.to_s.strip} - #{city.to_s.strip}"
      end)

      cities = city_labels.map { |label| { type: "city", label: label, value: label } }
      neighborhoods = neighborhood_labels.map { |label| { type: "neighborhood", label: label, value: label } }

      (cities + neighborhoods)
        .uniq { |item| [item[:type], normalize_location_value(item[:value])] }
        .sort_by { |item| [item[:type] == "city" ? 0 : 1, normalize_location_value(item[:label])] }
    end

    def canonical_location_labels(values)
      values
        .map(&:to_s)
        .reject { |value| value.strip.empty? }
        .group_by { |value| location_normalize_key(value) }
        .map { |_key, variants| titleize_location(most_common_location_label(variants)) }
        .uniq
        .sort_by { |label| location_normalize_key(label) }
    end

    def titleize_location(value)
      small_words = %w[de da do das dos e]
      value.to_s.strip.split(/\s+/).each_with_index.map do |word, index|
        downcased_word = word.downcase
        if index.positive? && small_words.include?(downcased_word)
          downcased_word
        else
          downcased_word[0].to_s.upcase + downcased_word[1..].to_s
        end
      end.join(" ")
    end

    def location_normalize_key(value)
      I18n.transliterate(value.to_s).downcase.gsub(/\s+/, " ").strip
    end

    def most_common_location_label(values)
      values
        .map { |value| value.to_s.strip }
        .max_by { |value| [values.count(value), value.length] }
    end

    def public_price_sort_sql(direction)
      normalized_direction = direction.to_s.upcase == "DESC" ? "DESC" : "ASC"
      price_sql = <<~SQL.squish
        CASE
          WHEN COALESCE(habitations.valor_venda_cents, 0) > 0 AND COALESCE(habitations.valor_locacao_cents, 0) > 0 THEN LEAST(habitations.valor_venda_cents, habitations.valor_locacao_cents)
          WHEN COALESCE(habitations.valor_venda_cents, 0) > 0 THEN habitations.valor_venda_cents
          WHEN COALESCE(habitations.valor_locacao_cents, 0) > 0 THEN habitations.valor_locacao_cents
          ELSE NULL
        END
      SQL

      "#{price_sql} #{normalized_direction} NULLS LAST, habitations.data_atualizacao_crm DESC, habitations.created_at DESC"
    end

    # Busca avançada SUPER DINÂMICA combinando múltiplos filtros
    def advanced_search(params = {}, base_scope: nil)
      params = params.to_h.with_indifferent_access
      query = base_scope || active # active já restringe a imóveis públicos com fotos e preço.
      
      # Tipo de transação
      query = query.for_sale if params[:transaction_type] == 'venda'
      query = query.for_rent if params[:transaction_type] == 'aluguel' || params[:transaction_type] == 'locacao'
      
      # Categoria
      query = query.by_category(params[:category]) if params[:category].present?
      
      # Localização (busca flexível - cidade OU bairro)
      if params[:city].present?
        if params[:city].is_a?(Array)
          query = query.by_public_locations(params[:city])
        else
          city_term = params[:city].to_s.strip
          query = query.left_outer_joins(:address).where(
            "#{LOCATION_CITY_NORM_SQL} ILIKE :term OR " \
            "#{LOCATION_NEIGHBORHOOD_NORM_SQL} ILIKE :term OR " \
            "#{LOCATION_LABEL_NORM_SQL} ILIKE :term OR " \
            "unaccent(nome_empreendimento) ILIKE unaccent(:term)",
            term: "%#{normalize_location_value(city_term)}%"
          )
        end
      end
      
      if params[:neighborhood].present?
        query = query.by_neighborhood(params[:neighborhood])
      end
      query = query.by_state(params[:state]) if params[:state].present?
      
      # Características numéricas
      query = query.with_min_bedrooms(params[:min_bedrooms]) if params[:min_bedrooms].present?
      query = query.with_min_suites(params[:min_suites]) if params[:min_suites].present?
      query = query.with_min_bathrooms(params[:min_bathrooms]) if params[:min_bathrooms].present?
      query = query.with_min_parking(params[:min_parking]) if params[:min_parking].present?
      
      # Área
      query = query.by_area_range(params[:min_area], params[:max_area]) if params[:min_area].present? || params[:max_area].present?
      
      # Característica Única (Badge Match)
      if params[:caracteristica_unica].present?
        feature_terms = Array(params[:caracteristica_unica]).reject(&:blank?)
        query = query.where(
          feature_terms.map {
            "EXISTS (" \
            "SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature " \
            "WHERE unaccent(feature) ILIKE unaccent(?)" \
            ")"
          }.join(" OR "),
          *feature_terms.map { |term| "%#{term}%" }
        )
      end

      # Preço Target (Range +/- 20%)
      if params[:target_price].present?
        target_value = params[:target_price].to_s.gsub(/\D/, '').to_i
        if target_value > 0
          min_price = (target_value * 0.8).to_i
          max_price = (target_value * 1.2).to_i
          
          if params[:transaction_type] == 'aluguel'
            query = query.where("valor_locacao_cents BETWEEN ? AND ?", min_price * 100, max_price * 100)
          else
            query = query.where("valor_venda_cents BETWEEN ? AND ?", min_price * 100, max_price * 100)
          end
        end
      end

      # Preço (baseado no tipo de transação)
      if params[:min_price].present? || params[:max_price].present?
        min_cents = params[:min_price].present? ? params[:min_price].to_s.gsub(/[^\d]/, '').to_i * 100 : 0
        max_cents = params[:max_price].present? ? params[:max_price].to_s.gsub(/[^\d]/, '').to_i * 100 : Float::INFINITY
        
        # Se tem tipo de transação específico, filtra apenas esse
        if params[:transaction_type] == 'venda'
          if min_cents > 0 && max_cents < Float::INFINITY
            query = query.where("valor_venda_cents BETWEEN ? AND ?", min_cents, max_cents)
          elsif min_cents > 0
            query = query.where("valor_venda_cents >= ?", min_cents)
          elsif max_cents < Float::INFINITY
            query = query.where("valor_venda_cents <= ?", max_cents)
          end
        elsif params[:transaction_type] == 'aluguel'
          # No site, o filtro de locação considera apenas o aluguel base.
          # Taxas como condomínio, IPTU e valor_total_aluguel_cents não entram nesta faixa.
          if min_cents > 0 && max_cents < Float::INFINITY
            query = query.where("valor_locacao_cents BETWEEN ? AND ?", min_cents, max_cents)
          elsif min_cents > 0
            query = query.where("valor_locacao_cents >= ?", min_cents)
          elsif max_cents < Float::INFINITY
            query = query.where("valor_locacao_cents <= ?", max_cents)
          end
        else
          # Se não especificou tipo, busca em ambos (venda OU locação dentro do range)
          if min_cents > 0 && max_cents < Float::INFINITY
            query = query.where(
              "(valor_venda_cents BETWEEN ? AND ?) OR (valor_locacao_cents BETWEEN ? AND ?)",
              min_cents, max_cents, min_cents, max_cents
            )
          elsif min_cents > 0
            query = query.where("valor_venda_cents >= ? OR valor_locacao_cents >= ?", min_cents, min_cents)
          elsif max_cents < Float::INFINITY
            query = query.where("valor_venda_cents <= ? OR valor_locacao_cents <= ?", max_cents, max_cents)
          end
        end
      end
      
      # Flags
      query = query.mobiliado if params[:furnished] == '1' || params[:furnished] == true
      query = query.aceita_permuta if params[:accepts_exchange] == '1' || params[:accepts_exchange] == true
      query = query.aceita_financiamento if params[:accepts_financing] == '1' || params[:accepts_financing] == true
      
      # Características específicas
      query = query.frente_mar if params[:frente_mar] == '1' || params[:frente_mar] == true
      query = query.quadra_mar if params[:quadra_mar] == '1' || params[:quadra_mar] == true
      query = query.varanda if params[:varanda] == '1' || params[:varanda] == true
      
      # Características via array (agora com lógica OU para ser aditivo)
      if params[:characteristics].present?
        characteristics = params[:characteristics].is_a?(Array) ? params[:characteristics] : [params[:characteristics]]
        
        # Criamos um sub-query que será unido por OR
        char_conditions = Habitation.none
        
        characteristics.each do |char|
          case char.to_s
          when 'featured' then char_conditions = char_conditions.or(Habitation.featured)
          when 'frente_mar' then char_conditions = char_conditions.or(Habitation.frente_mar)
          when 'quadra_mar' then char_conditions = char_conditions.or(Habitation.quadra_mar)
          when 'vista_mar' then char_conditions = char_conditions.or(Habitation.vista_mar)
          when 'churrasqueira' then char_conditions = char_conditions.or(Habitation.churrasqueira)
          when 'cozinha_gourmet_churrasqueira' then char_conditions = char_conditions.or(Habitation.cozinha_gourmet_churrasqueira)
          when 'mobiliado' then char_conditions = char_conditions.or(Habitation.mobiliado)
          when 'sacada' then char_conditions = char_conditions.or(Habitation.sacada)
          when 'decorado' then char_conditions = char_conditions.or(Habitation.decorado)
          when 'closet' then char_conditions = char_conditions.or(Habitation.closet)
          when 'semi_mobiliado' then char_conditions = char_conditions.or(Habitation.semi_mobiliado)
          when 'lavabo' then char_conditions = char_conditions.or(Habitation.lavabo)
          when 'lavanderia' then char_conditions = char_conditions.or(Habitation.lavanderia)
          when 'dependencia_empregada' then char_conditions = char_conditions.or(Habitation.dependencia_empregada)
          when 'sol_manha' then char_conditions = char_conditions.or(Habitation.sol_manha)
          when 'sol_tarde' then char_conditions = char_conditions.or(Habitation.sol_tarde)
          when 'sol_dia_todo' then char_conditions = char_conditions.or(Habitation.sol_dia_todo)
          when 'hidromassagem' then char_conditions = char_conditions.or(Habitation.hidromassagem)
          when 'piscina' then char_conditions = char_conditions.or(Habitation.piscina)
          when 'sala_estar' then char_conditions = char_conditions.or(Habitation.sala_estar)
          when 'sala_jantar' then char_conditions = char_conditions.or(Habitation.sala_jantar)
          when 'varanda' then char_conditions = char_conditions.or(Habitation.varanda)
          when 'lancamento_flag' then char_conditions = char_conditions.or(Habitation.lancamento)
          when 'aceita_permuta_flag' then char_conditions = char_conditions.or(Habitation.aceita_permuta)
          when 'aceita_financiamento_flag' then char_conditions = char_conditions.or(Habitation.aceita_financiamento)
          when 'garden_flag' then char_conditions = char_conditions.or(Habitation.garden)
          when 'festival_salute_flag' then char_conditions = char_conditions.or(Habitation.festival_salute)
          when 'exibir_no_site_flag', 'exibir_no_site_salute_flag' then char_conditions = char_conditions.or(Habitation.exibir_site_salute)
          when 'opportunity' then char_conditions = char_conditions.or(Habitation.opportunity)
          when 'na_planta' then char_conditions = char_conditions.or(Habitation.na_planta)
          when 'lancamento' then char_conditions = char_conditions.or(Habitation.lancamento)
          when 'pronto' then char_conditions = char_conditions.or(Habitation.pronto)
          when 'em_construcao' then char_conditions = char_conditions.or(Habitation.em_construcao)
          end
        end
        
        # Aplicamos o grupo de ORs à query principal via subseleção de IDs
        query = query.where(id: char_conditions.select(:id)) if characteristics.any?
      end
      
      # Busca textual geral (título, descrição, endereço, código)
      if params[:search].present?
        search_term = params[:search].strip
        
        # Busca em campos principais
        query = query.left_outer_joins(:address).where(
          "unaccent(titulo_anuncio) ILIKE unaccent(:q) OR " \
          "unaccent(descricao_web) ILIKE unaccent(:q) OR " \
          "unaccent(COALESCE(addresses.logradouro, habitations.endereco)) ILIKE unaccent(:q) OR " \
          "unaccent(COALESCE(addresses.bairro, habitations.bairro)) ILIKE unaccent(:q) OR " \
          "unaccent(COALESCE(addresses.cidade, habitations.cidade)) ILIKE unaccent(:q) OR " \
          "unaccent(nome_empreendimento) ILIKE unaccent(:q) OR " \
          "codigo ILIKE :q OR " \
          "EXISTS (SELECT 1 FROM unnest((#{UNIQUE_FEATURES_ARRAY_SQL})) AS feature WHERE unaccent(feature) ILIKE unaccent(:q)) OR " \
          "EXISTS (SELECT 1 FROM jsonb_each_text(caracteristicas) WHERE unaccent(lower(value)) ILIKE unaccent(:q)) OR " \
          "(jsonb_typeof(infra_estrutura) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(infra_estrutura) WHERE unaccent(lower(value)) ILIKE unaccent(:q)))",
          q: "%#{search_term}%"
        )
      end
      
      # Ordenação
      query = apply_sorting(query, params[:sort])
      
      query
    end

    def public_property_search(params = {})
      advanced_search(params, base_scope: public_property_listable)
    end
    
    # Aplica ordenação baseada em parâmetro
    def apply_sorting(query, sort_param)
      case sort_param.to_s
      when 'price_asc'
        query.price_asc
      when 'price_desc'
        query.price_desc
      when 'area_asc'
        query.area_asc
      when 'area_desc'
        query.area_desc
      when 'oldest'
        query.oldest_first
      else
        query.newest_first
      end
    end
  end
end
