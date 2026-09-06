module HabitationQuickFilters
  QUICK_FILTERS = {"destaque_web" => "Destaque Web", "oportunidade" => "Oportunidade", "frente_mar" => "Frente Mar", "lancamento" => "Lançamento", "na_planta" => "Na Planta", "mobiliado" => "Mobiliado", "semi_mobiliado" => "Semi mobiliado", "sem_mobilia" => "Sem mobília", "diferenciado" => "Diferenciado", "quadra_mar" => "Quadra mar", "dependencia_empregada" => "Dependência", "cozinha_gourmet_churrasqueira" => "Cozinha gourmet", "sol_manha" => "Sol manhã", "sol_tarde" => "Sol tarde", "sol_dia_todo" => "Sol dia todo", "decorado" => "Decorado"}.freeze

  private

  def apply_quick_scope_filter(scope, raw_scope)
    case raw_scope
    when "destaque_web"
      scope.where(destaque_web_flag: true)
    when "super_destaque"
      scope.where(Habitation.physical_column_name(:festival_flag) => true)
    when "oportunidade"
      scope.opportunity
    when "frente_mar"
      apply_front_sea_filter(scope)
    when "lancamento"
      scope.where(lancamento_flag: true)
    when "na_planta"
      scope.where("unaccent(COALESCE(habitations.situacao, '')) ILIKE unaccent(?) OR unaccent(COALESCE(habitations.situacao, '')) = unaccent(?)", "%Planta%", "Construção")
    when "mobiliado"
      apply_catalog_text_feature_filter(scope, "mobiliado", boolean_column: :mobiliado_flag)
    when "semi_mobiliado"
      scope.semi_mobiliado
    when "sem_mobilia"
      apply_catalog_text_feature_filter(scope, "sem mob", boolean_column: :sem_mobilia_flag)
    when "diferenciado"
      scope.diferenciado
    when "quadra_mar"
      scope.quadra_mar
    when "dependencia_empregada"
      scope.dependencia_empregada
    when "cozinha_gourmet_churrasqueira"
      scope.cozinha_gourmet_churrasqueira
    when "sol_manha"
      scope.sol_manha
    when "sol_tarde"
      scope.sol_tarde
    when "sol_dia_todo"
      scope.sol_dia_todo
    when "decorado"
      apply_catalog_text_feature_filter(scope, "decorad", boolean_column: :decorado_flag)
    else
      scope
    end
  end

  def apply_front_sea_filter(scope)
    Habitations::AmenityFilter.call(scope, "Frente mar")
  end

  def apply_catalog_text_feature_filter(scope, term, boolean_column: nil)
    fragments = []
    fragments << "habitations.#{ActiveRecord::Base.connection.quote_column_name(boolean_column)} IS TRUE" if boolean_column.present?
    fragments << "(jsonb_typeof(habitations.caracteristicas) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(habitations.caracteristicas) value WHERE unaccent(value) ILIKE unaccent(:term_pattern)))"
    fragments << "(jsonb_typeof(habitations.caracteristicas) = 'object' AND EXISTS (SELECT 1 FROM jsonb_each_text(habitations.caracteristicas) kv WHERE unaccent(kv.key) ILIKE unaccent(:term_pattern) OR unaccent(kv.value) ILIKE unaccent(:term_pattern)))"
    fragments << "EXISTS (SELECT 1 FROM unnest((#{Habitation::SearchScopes::UNIQUE_FEATURES_ARRAY_SQL})) AS feature WHERE unaccent(feature) ILIKE unaccent(:term_pattern))"

    scope.where(fragments.join(" OR "), term_pattern: "%#{term}%")
  end

end
