class AutocompleteController < ApplicationController
  def locations
    query = params[:query].to_s.strip
    
    # Se query vazia, retornar localizações populares
    if query.blank?
      popular = popular_locations
      return render json: popular
    end
    
    # Buscar cidades, bairros e empreendimentos
    results = []
    
    # Cidades (usando unaccent para ignorar acentos)
    cities = Habitation.active
      .left_outer_joins(:address)
      .where("unaccent(COALESCE(addresses.cidade, habitations.cidade)) ILIKE unaccent(?)", "%#{query}%")
      .distinct
      .limit(5)
      .pluck(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
      .compact
      .map { |city| { type: 'Cidade', value: city, label: city } }
    
    # Bairros com cidade (usando unaccent)
    neighborhoods = Habitation.active
      .left_outer_joins(:address)
      .where("unaccent(COALESCE(addresses.bairro, habitations.bairro)) ILIKE unaccent(?) OR unaccent(COALESCE(addresses.cidade, habitations.cidade)) ILIKE unaccent(?)", "%#{query}%", "%#{query}%")
      .select("COALESCE(addresses.bairro, habitations.bairro) AS bairro_nome, COALESCE(addresses.cidade, habitations.cidade) AS cidade_nome")
      .distinct
      .limit(5)
      .map { |h| { type: 'Bairro', value: h.bairro_nome, label: "#{h.bairro_nome} - #{h.cidade_nome}" } }
      .compact
    
    # Empreendimentos (usando unaccent)
    developments = Habitation.empreendimentos_publicos
      .where("unaccent(nome_empreendimento) ILIKE unaccent(?)", "%#{query}%")
      .where.not(nome_empreendimento: nil)
      .left_outer_joins(:address)
      .select("nome_empreendimento, COALESCE(addresses.cidade, habitations.cidade) AS cidade_nome")
      .distinct
      .limit(5)
      .map { |h| { type: 'Empreendimento', value: h.nome_empreendimento, label: "#{h.nome_empreendimento} - #{h.cidade_nome}" } }
    
    results = cities + neighborhoods + developments
    
    render json: results.uniq.take(10)
  end
  
  private
  
  def popular_locations
    # Retornar as cidades/bairros com mais imóveis
    popular_cities = Habitation.active
      .left_outer_joins(:address)
      .group(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
      .order('count_all DESC')
      .limit(5)
      .count
      .keys
      .map { |city| { type: 'Cidade', value: city, label: city } }
    
    popular_neighborhoods = Habitation.active
      .left_outer_joins(:address)
      .where("COALESCE(addresses.bairro, habitations.bairro) IS NOT NULL")
      .group(Arel.sql("COALESCE(addresses.bairro, habitations.bairro)"))
      .group(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
      .order('count_all DESC')
      .limit(5)
      .count
      .keys
      .map { |bairro, cidade| { type: 'Bairro', value: bairro, label: "#{bairro} - #{cidade}" } }
    
    (popular_cities + popular_neighborhoods).take(8)
  end
end
