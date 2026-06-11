require 'thor'
require 'rest-client'
require 'json'

class CheckVistaFields < Thor
  VISTA_URL = "http://saluteim20174-rest.vistahost.com.br"
  VISTA_KEY = "ea83a702a7669520304be011258289fd"

  desc "properties", "Check property fields"
  def properties
    url = "#{VISTA_URL}/imoveis/listar"
    
    query = { fields: ['Codigo'], paginacao: { pagina: 1, quantidade: 1 } }
    params = { key: VISTA_KEY, pesquisa: query.to_json }

    response = RestClient.get(url, { params: params, accept: :json })
    first_imovel = JSON.parse(response.body).values.find { |v| v.is_a?(Hash) && v['Codigo'] }
    codigo = first_imovel['Codigo']

    puts "Fetching details for property #{codigo}..."
    details_url = "#{VISTA_URL}/imoveis/detalhes"
    
    # Requesting only the promising ones
    fields = ['Codigo', 'DataCadastro', 'DataAtualizacao', 'DataEntrega']
    payload = { fields: fields }
    
    details_params = { key: VISTA_KEY, imovel: codigo, pesquisa: payload.to_json }
    
    begin
      details_resp = RestClient.get(details_url, { params: details_params, accept: :json })
      details = JSON.parse(details_resp.body)

      puts "\nFound Fields:"
      details.each { |k, v| puts "  #{k}: #{v}" }
    rescue RestClient::ExceptionWithResponse => e
      puts "Error: #{e.http_code}"
      puts e.response.body
    end
  end

  def self.exit_on_failure?
    true
  end
end

CheckVistaFields.start(ARGV)
