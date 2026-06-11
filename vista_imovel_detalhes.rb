#!/usr/bin/env ruby
# Consulta completa de um imovel na API Vista da Salute.
# Uso:
#   ruby vista_imovel_detalhes.rb
#   ruby vista_imovel_detalhes.rb 8614
#
# Tambem aceita sobrescrever via ENV:
#   VISTA_HOST=http://... VISTA_KEY=... ruby vista_imovel_detalhes.rb 8614

require "json"
require "net/http"
require "uri"

ROOT = File.expand_path(__dir__)
DEFAULT_HOST = "http://saluteim20174-rest.vistahost.com.br"
CHUNK_SIZE = 55
$stdout.sync = true
$stderr.sync = true

def log(message)
  warn "[vista] #{message}"
end

def load_dotenv(path)
  return unless File.exist?(path)

  File.readlines(path).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#") || !line.include?("=")

    key, value = line.split("=", 2)
    ENV[key] ||= value.to_s.strip.gsub(/\A['"]|['"]\z/, "")
  end
end

def get_json(url, params)
  uri = URI(url)
  uri.query = URI.encode_www_form(params)
  request = Net::HTTP::Get.new(uri)
  request["Accept"] = "application/json"

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.read_timeout = 60
    http.open_timeout = 15
    http.request(request)
  end

  parsed = JSON.parse(response.body)
  unless response.is_a?(Net::HTTPSuccess)
    message = parsed["message"] || parsed["msg"] || response.message
    raise "HTTP #{response.code}: #{message}"
  end

  parsed
rescue JSON::ParserError
  raise "Resposta nao e JSON valido para #{uri}"
end

def deep_merge(left, right)
  left.merge(right) do |_key, old_value, new_value|
    if old_value.is_a?(Hash) && new_value.is_a?(Hash)
      deep_merge(old_value, new_value)
    elsif old_value.is_a?(Array) && new_value.is_a?(Array)
      (old_value + new_value).uniq
    else
      new_value.nil? || new_value == "" ? old_value : new_value
    end
  end
end

def request_details(host, key, codigo, fields)
  get_json(
    "#{host}/imoveis/detalhes",
    key: key,
    imovel: codigo,
    showSuspended: 1,
    pesquisa: { fields: fields }.to_json
  )
end

def merge_response!(result, response)
  unless response.is_a?(Hash)
    result["_meta"]["avisos"] << {
      "tipo" => "resposta_ignorada",
      "classe" => response.class.name,
      "valor" => response
    }
    return result
  end

  deep_merge(result, response)
end

def fetch_available_fields(host, key)
  get_json("#{host}/imoveis/listarcampos", key: key)
end

def prompt_codigo
  warn "Codigo do imovel: "
  STDIN.gets.to_s.strip
end

load_dotenv(File.join(ROOT, ".env.development"))
load_dotenv(File.join(ROOT, ".env"))

host = ENV.fetch("VISTA_HOST", DEFAULT_HOST).to_s.sub(%r{/*\z}, "")
key = ENV["VISTA_KEY"].to_s.strip
codigo = ARGV[0].to_s.strip
codigo = prompt_codigo if codigo.empty?

if key.empty?
  warn "VISTA_KEY nao informado. Defina em .env.development, .env ou no ambiente."
  exit 1
end

if codigo.empty?
  warn "Codigo do imovel nao informado."
  exit 1
end

begin
  log "Consultando campos disponiveis da Salute..."
  available = fetch_available_fields(host, key)
  result = {
    "_meta" => {
      "host" => host,
      "codigo_consultado" => codigo,
      "listarcampos_keys" => available.keys,
      "avisos" => []
    }
  }

  top_level_fields = Array(available["imoveis"]).uniq
  %w[Caracteristicas InfraEstrutura].each do |field|
    top_level_fields << field unless top_level_fields.include?(field)
  end

  log "Consultando #{top_level_fields.size} campos principais do imovel #{codigo}..."
  top_level_fields.each_slice(CHUNK_SIZE) do |fields_chunk|
    log "Campos principais #{fields_chunk.first}..#{fields_chunk.last}"
    result = merge_response!(result, request_details(host, key, codigo, fields_chunk))
  rescue StandardError => e
    log "Grupo de campos principais falhou; tentando campo a campo..."
    fields_chunk.each do |field|
      begin
        result = merge_response!(result, request_details(host, key, codigo, [field]))
      rescue StandardError => single_error
        result["_meta"]["avisos"] << {
          "tipo" => "falha_campo_principal",
          "field" => field,
          "erro" => single_error.message
        }
      end
    end

    result["_meta"]["avisos"] << {
      "tipo" => "falha_campos_principais",
      "fields" => fields_chunk,
      "erro" => e.message
    }
  end

  association_keys = available.keys - ["imoveis", "codigo", "carac", "infra"]
  log "Consultando associacoes: #{association_keys.join(', ')}"
  association_keys.each do |association|
    fields = Array(available[association]).uniq
    next if fields.empty?

    log "Associacao #{association} (#{fields.size} campos)..."
    fields.each_slice(CHUNK_SIZE) do |fields_chunk|
      result = merge_response!(result, request_details(host, key, codigo, [{ association => fields_chunk }]))
    rescue StandardError => e
      log "Associacao #{association} falhou em lote; tentando campo a campo..."
      fields_chunk.each do |field|
        begin
          result = merge_response!(result, request_details(host, key, codigo, [{ association => [field] }]))
        rescue StandardError => single_error
          result["_meta"]["avisos"] << {
            "tipo" => "falha_campo_associacao",
            "associacao" => association,
            "field" => field,
            "erro" => single_error.message
          }
        end
      end

      result["_meta"]["avisos"] << {
        "tipo" => "falha_associacao",
        "associacao" => association,
        "fields" => fields_chunk,
        "erro" => e.message
      }
    end
  end

  result["_meta"]["total_campos_principais_solicitados"] = top_level_fields.size
  result["_meta"]["associacoes_solicitadas"] = association_keys

  log "Consulta finalizada. Imprimindo JSON..."
  puts JSON.pretty_generate(result)
rescue StandardError => e
  warn "Erro ao consultar imovel #{codigo}: #{e.message}"
  exit 1
end
