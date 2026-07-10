class EmpreendimentosController < ApplicationController
  def index
    @page_name = 'empreendimentos'
    @strategic_landing = Seo::StrategicLanding.development(params[:seo_slug])
    
    # Base scope: only 'Empreendimento' type
    @empreendimentos = public_habitations.empreendimentos_publicos.left_outer_joins(:address).order(nome_empreendimento: :asc)
    @empreendimentos = apply_strategic_landing_scope(@empreendimentos)

    # Filter by search term if present
    if params[:q].present?
      term = "%#{params[:q].downcase}%"
      @empreendimentos = @empreendimentos.where("unaccent(nome_empreendimento) ILIKE unaccent(?)", term)
    end

    # Pagination
    @empreendimentos = @empreendimentos.paginate(page: params[:page], per_page: 20)
    PublicSite::CardPhotoPreloader.new(@empreendimentos.to_a, limit: 1).call

    # Calculate unit counts for the current page to avoid N+1 on the whole table
    # We can do a group count query for all habitations that match these development codes
    development_codes = @empreendimentos.map(&:codigo).compact
    
    @unit_counts = public_habitations.where.not(codigo_empreendimento: nil)
                             .where(codigo_empreendimento: development_codes)
                             .group(:codigo_empreendimento)
                             .count

    if @strategic_landing.present?
      @page_title = "#{@strategic_landing[:title]} | #{public_site_name}"
      @page_description = @strategic_landing[:description]
      @page_keywords = [@strategic_landing[:label], "empreendimentos", "Balneário Camboriú", public_site_name].join(", ")
    end
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
end
