class EmpreendimentosController < ApplicationController
  MAX_PUBLIC_DEVELOPMENT_PAGE = ENV.fetch("PUBLIC_DEVELOPMENT_MAX_PAGE", 50).to_i
  # Fase → scope de Habitation (os mesmos da busca de imóveis).
  DEVELOPMENT_PHASES = { "lancamento" => "Lançamento", "em_construcao" => "Em obras", "pronto" => "Pronto para morar" }.freeze
  DEVELOPMENT_SORTS = { "unidades" => "Mais unidades disponíveis", "recentes" => "Mais recentes", "nome" => "Nome (A–Z)" }.freeze

  def index
    return if reject_invalid_public_development_page!

    @page_name = 'empreendimentos'
    @strategic_landing = Seo::StrategicLanding.development(params[:seo_slug])
    
    # O botão flutuante é da busca de imóveis; aqui a barra de filtros já busca.
    @hide_global_search = true

    base_scope = public_habitations.empreendimentos_publicos.left_outer_joins(:address)
    @development_names = base_scope.distinct.order(:nome_empreendimento).pluck(:nome_empreendimento).compact_blank
    @development_city_options = Habitation.canonical_location_labels(
      base_scope.distinct.pluck(Arel.sql(Habitation::LOCATION_CITY_SQL))
    )

    @empreendimentos = apply_strategic_landing_scope(base_scope)
    @empreendimentos = @empreendimentos.where("unaccent(nome_empreendimento) ILIKE unaccent(?)", "%#{params[:q]}%") if params[:q].present?
    @selected_phase = DEVELOPMENT_PHASES.key?(params[:fase].to_s) ? params[:fase].to_s : nil
    @empreendimentos = @empreendimentos.public_send(@selected_phase) if @selected_phase
    @selected_city = params[:cidade].to_s.presence
    @empreendimentos = apply_location_filter(@empreendimentos, [@selected_city]) if @selected_city
    @selected_sort = DEVELOPMENT_SORTS.key?(params[:ordem].to_s) ? params[:ordem].to_s : "unidades"
    @empreendimentos = order_developments(@empreendimentos, @selected_sort)

    @empreendimentos = @empreendimentos.paginate(page: requested_public_development_page, per_page: 21)
    PublicSite::CardPhotoPreloader.new(@empreendimentos.to_a, limit: 1).call

    # Números dos cards em lote (uma consulta por página, não por card).
    development_metrics = PublicSite::DevelopmentUnitMetrics.new(public_habitations, @empreendimentos.map(&:codigo))
    @unit_counts = development_metrics.unit_counts
    @unit_metrics = development_metrics.unit_metrics

    if @strategic_landing.present?
      @page_title = "#{@strategic_landing[:title]} | #{public_site_name}"
      @page_description = @strategic_landing[:description]
      @page_keywords = [@strategic_landing[:label], "empreendimentos", default_public_city, public_site_name].compact_blank.join(", ")
    end

    expires_in 15.minutes, public: true unless params[:q].present?
  end

  def search
    term = params[:q]
    return render json: [] if term.blank?

    # Autocomplete search
    results = public_habitations.empreendimentos_publicos
                        .where("unaccent(nome_empreendimento) ILIKE unaccent(?)", "%#{term}%")
                        .limit(10)
                        .pluck(:nome_empreendimento, :codigo)
                        .map { |name, code| { label: name, value: name } } # value is name for search param

    render json: results
  end

  private

  def requested_public_development_page
    raw_page = params[:page].presence
    return 1 if raw_page.blank?

    raw_page = raw_page.to_s
    return nil unless raw_page.match?(/\A\d+\z/)

    raw_page.to_i
  end

  def reject_invalid_public_development_page!
    page = requested_public_development_page
    return false if page.present? && page.between?(1, MAX_PUBLIC_DEVELOPMENT_PAGE)

    Rails.logger.info(
      "[PublicDevelopmentPageGuard] rejected invalid page=#{params[:page].inspect} " \
      "ip=#{request.remote_ip} path=#{request.fullpath}"
    )
    render plain: "Not Found", status: :not_found
    true
  end

  def order_developments(scope, sort)
    case sort
    when "recentes" then scope.order(created_at: :desc, id: :desc)
    when "nome" then scope.order(nome_empreendimento: :asc)
    else
      units_sql = "(SELECT COUNT(*) FROM habitations units WHERE units.tenant_id = habitations.tenant_id " \
                  "AND units.codigo_empreendimento = habitations.codigo)"
      scope.order(Arel.sql("#{units_sql} DESC"), nome_empreendimento: :asc)
    end
  end

  def apply_strategic_landing_scope(scope)
    return scope if @strategic_landing.blank?

    params_hash = @strategic_landing[:params]
    scope = apply_location_filter(scope, Array(params_hash[:city]))
    Array(params_hash[:characteristics]).reduce(scope) do |current_scope, characteristic|
      current_scope.respond_to?(characteristic) ? current_scope.public_send(characteristic) : current_scope
    end
  end

  def apply_location_filter(scope, locations)
    locations.reject(&:blank?).reduce(scope) do |current_scope, location|
      bairro, cidade = parse_location(location)
      if bairro.present? && cidade.present?
        current_scope.where(
          "unaccent(COALESCE(addresses.bairro, habitations.bairro)) ILIKE unaccent(?) AND unaccent(COALESCE(addresses.cidade, habitations.cidade)) ILIKE unaccent(?)",
          bairro,
          cidade
        )
      else
        current_scope.where(
          "unaccent(COALESCE(addresses.cidade, habitations.cidade, addresses.bairro, habitations.bairro)) ILIKE unaccent(?)",
          location
        )
      end
    end
  end

  def parse_location(value)
    parts = value.to_s.split(" - ", 2).map(&:strip)
    parts.size == 2 ? parts : [nil, value]
  end

  def public_site_name
    @layout_setting&.site_name.presence || LayoutSetting.instance.site_name.presence || "Unitymob"
  rescue StandardError
    "Unitymob"
  end


  def default_public_city
    Tenants::PublicIdentity.new(public_tenant).primary_city.presence || "Brasil"
  end
end
