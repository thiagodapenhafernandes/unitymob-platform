class BrokersController < ApplicationController
  def index
    @page_name = 'corretores'
    @brokers = fetch_brokers_from_admin_users
  end

  private

  def fetch_brokers_from_admin_users
    AdminUser
      .active
      .displayed_on_site
      .joins(:profile)
      .where(profiles: { name: %w[Corretor Gerente] })
      .with_attached_avatar
      .order(:name)
  end

  def fetch_brokers_from_vista
    require 'cgi'
    
    data = {
      'fields' => [
        "Codigo",
        "E-mail",
        "Nomecompleto",
        "Celular",
        "CRECI",
        "Foto",
        "Observacoes",
        "Exibirnosite",
        "Inativo",
        "Atuaçãoemvenda",
        "Atuaçãoemlocação"
      ],
      'paginacao' => { "pagina" => 1, "quantidade" => 50 }
    }

    key = 'ea83a702a7669520304be011258289fd'
    host = 'http://saluteim20174-rest.vistahost.com.br/usuarios/listar?key=' + key
    post_fields = '&pesquisa=' + CGI.escape(ActiveSupport::JSON.encode(data))
    url = host + post_fields

    headers = { 'Accept': 'application/json' }

    response = JSON.parse(RestClient.get(url + '&showtotal=1&show', headers))
    
    Rails.logger.info "Vista API Response class: #{response.class}"
    
    # Vista returns a hash with broker codes as keys
    if response.is_a?(Hash)
      # Extract broker data, excluding pagination fields
      brokers = response.except('total', 'paginas', 'pagina', 'quantidade').values
      
      Rails.logger.info "Total brokers from API: #{brokers.count}"
      
      # Filter only active brokers that should be displayed on site AND have photos
      # Vista uses "Sim"/"Nao" strings, not booleans
      filtered = brokers.select do |broker|
        broker.is_a?(Hash) && 
        broker['Exibirnosite'] == 'Sim' && 
        broker['Inativo'] == 'Nao' &&
        broker['Foto'].present? && broker['Foto'].to_s.strip != ''
      end
      
      Rails.logger.info "Filtered brokers count (active with photos): #{filtered.count}"
      filtered
    elsif response.is_a?(Array)
      # Fallback for array format
      filtered = response.select do |broker|
        broker['Exibirnosite'] == 'Sim' && 
        broker['Inativo'] == 'Nao' &&
        broker['Foto'].present? && broker['Foto'].to_s.strip != ''
      end
      Rails.logger.info "Filtered brokers count (from array, with photos): #{filtered.count}"
      filtered
    else
      Rails.logger.warn "Unexpected response format: #{response.class}"
      []
    end
  rescue => e
    Rails.logger.error "Error fetching brokers from Vista: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    []
  end
end
