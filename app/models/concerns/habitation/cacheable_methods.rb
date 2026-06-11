module Habitation::CacheableMethods
  extend ActiveSupport::Concern
  
  # Cache para métodos que não mudam frequentemente
  CACHE_EXPIRATION = 1.hour
  
  # Retorna área formatada com cache
  def area_formatted
    Rails.cache.fetch([cache_key, 'area_formatted'], expires_in: CACHE_EXPIRATION) do
      calculate_area_formatted
    end
  end
  
  # Retorna título do card com cache
  def card_title
    Rails.cache.fetch([cache_key, 'card_title'], expires_in: CACHE_EXPIRATION) do
      display_title.presence || default_title
    end
  end
  
  # Retorna descrição resumida com cache
  def short_description(length = 150)
    Rails.cache.fetch([cache_key, "short_description_#{length}"], expires_in: CACHE_EXPIRATION) do
      return '' if descricao_web.blank?
      
      text = descricao_web.strip
      if text.length > length
        "#{text[0...length]}..."
      else
        text
      end
    end
  end
  
  # Retorna endereço completo formatado com cache
  def full_address
    Rails.cache.fetch([cache_key, 'full_address'], expires_in: CACHE_EXPIRATION) do
      calculate_full_address
    end
  end
  
  # Retorna endereço resumido com cache
  def short_address
    Rails.cache.fetch([cache_key, 'short_address'], expires_in: CACHE_EXPIRATION) do
      parts = []
      parts << bairro if bairro.present?
      parts << cidade if cidade.present?
      parts.join(', ')
    end
  end
  
  # Retorna características principais com cache
  def main_features
    Rails.cache.fetch([cache_key, 'main_features'], expires_in: CACHE_EXPIRATION) do
      calculate_main_features
    end
  end
  
  # Retorna URL da imagem principal com cache
  def primary_image_url
    Rails.cache.fetch([cache_key, 'primary_image_url'], expires_in: CACHE_EXPIRATION) do
      img = primary_image
      img.is_a?(Hash) ? img['url'] || img[:url] : img
    end
  end
  
  # Retorna todas as URLs de imagens com cache
  def image_urls
    Rails.cache.fetch([cache_key, 'image_urls'], expires_in: CACHE_EXPIRATION) do
      all_images.map do |img|
        img.is_a?(Hash) ? (img['url'] || img[:url]) : img
      end.compact
    end
  end
  
  # Retorna dados formatados para card com cache
  def card_data
    Rails.cache.fetch([cache_key, 'card_data'], expires_in: CACHE_EXPIRATION) do
      {
        id: id,
        codigo: codigo,
        slug: slug,
        title: card_title,
        category: categoria,
        status: status,
        price: preco_principal,
        address: short_address,
        bedrooms: dormitorios_qtd,
        suites: suites_qtd,
        bathrooms: banheiros_qtd,
        parking: vagas_qtd,
        area: area_total_m2&.to_i,
        area_formatted: area_formatted,
        image: primary_image_url,
        images: image_urls,
        featured: destaque_web_flag,
        new_launch: lancamento_flag,
        badges: display_badges,
        url: "/imovel/#{slug}"
      }
    end
  end
  
  private
  
  def calculate_area_formatted
    return nil unless area_total_m2.present? && area_total_m2 > 0
    
    area = area_total_m2.to_i
    "#{area} m²"
  end
  
  def calculate_full_address
    parts = []
    
    if tipo_endereco.present? && endereco.present?
      parts << "#{tipo_endereco} #{endereco}"
      parts.last << ", #{numero}" if numero.present?
    elsif endereco.present?
      parts << endereco
      parts.last << ", #{numero}" if numero.present?
    end
    
    parts << complemento if complemento.present?
    parts << bairro if bairro.present?
    parts << "#{cidade} - #{uf}" if cidade.present? && uf.present?
    parts << cidade if cidade.present? && uf.blank?
    parts << "CEP #{cep}" if cep.present?
    
    parts.join(', ')
  end
  
  def calculate_main_features
    features = []
    
    if dormitorios_qtd.to_i > 0
      features << {
        icon: 'bed',
        label: 'Dormitórios',
        value: dormitorios_qtd,
        text: "#{dormitorios_qtd} #{dormitorios_qtd == 1 ? 'dormitório' : 'dormitórios'}"
      }
    end
    
    if suites_qtd.to_i > 0
      features << {
        icon: 'star',
        label: 'Suítes',
        value: suites_qtd,
        text: "#{suites_qtd} #{suites_qtd == 1 ? 'suíte' : 'suítes'}"
      }
    end
    
    if banheiros_qtd.to_i > 0
      features << {
        icon: 'bath',
        label: 'Banheiros',
        value: banheiros_qtd,
        text: "#{banheiros_qtd} #{banheiros_qtd == 1 ? 'banheiro' : 'banheiros'}"
      }
    end
    
    if vagas_qtd.to_i > 0
      features << {
        icon: 'car',
        label: 'Vagas',
        value: vagas_qtd,
        text: "#{vagas_qtd} #{vagas_qtd == 1 ? 'vaga' : 'vagas'}"
      }
    end
    
    if area_total_m2.to_f > 0
      features << {
        icon: 'ruler',
        label: 'Área',
        value: area_total_m2.to_i,
        text: area_formatted
      }
    end
    
    features
  end
end
