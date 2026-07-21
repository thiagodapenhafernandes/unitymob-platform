require "csv"
require "fileutils"
require "json"
require "rest-client"
require "thread"
require "time"

tenant_id = ENV["TENANT_ID"].presence
tenant = tenant_id.present? ? Tenant.find(tenant_id) : Tenant.default
Current.tenant = tenant if defined?(Current)

timestamp = "#{Time.current.strftime("%Y%m%d_%H%M%S")}_#{Process.pid}"
output_dir = ENV.fetch("OUTPUT_DIR", Rails.root.join("tmp", "owner_audit", timestamp).to_s)
FileUtils.mkdir_p(output_dir)

workers = [ENV.fetch("WORKERS", "6").to_i, 1].max
limit = ENV.fetch("LIMIT", "0").to_i
codes_filter = ENV.fetch("CODES", "").split(",").map(&:strip).reject(&:blank?).to_set
validate_api = ActiveModel::Type::Boolean.new.cast(ENV.fetch("VALIDATE_API", "true"))
host = ENV.fetch("VISTA_HOST")
key = ENV.fetch("VISTA_KEY")

FIELDS = [
  "Proprietario",
  "CodigoProprietario",
  { "proprietarios" => ["Nome", "Email", "Celular", "FoneComercial", "FoneResidencial"] },
  "Corretor",
  "CodigoCorretor",
  "DataAtualizacao",
  "Status",
  "Situacao"
].freeze

def normalize_code(value)
  value.to_s.strip.presence
end

def normalize_text(value)
  value.to_s.strip.gsub(/\s+/, " ").downcase.presence
end

def owner_data(api)
  raw = api["proprietarios"]
  case raw
  when Hash
    raw.values.find { |item| item.is_a?(Hash) } || {}
  when Array
    raw.find { |item| item.is_a?(Hash) } || {}
  else
    {}
  end
end

def api_owner_name(api)
  data = owner_data(api)
  api["Proprietario"].presence || data["Nome"].presence
end

def fetch_vista_owner(host, key, codigo)
  params = {
    key: key,
    imovel: codigo,
    pesquisa: { fields: FIELDS }.to_json,
    showSuspended: 1
  }

  response = RestClient.get("#{host}/imoveis/detalhes", params: params, accept: :json)
  parsed = JSON.parse(response.body)
  return parsed if parsed.is_a?(Hash)

  { "_error" => "invalid_response" }
rescue RestClient::ExceptionWithResponse => e
  message = begin
    parsed = JSON.parse(e.response&.body.to_s)
    parsed["message"].presence || parsed["msg"].presence
  rescue StandardError
    nil
  end
  { "_error" => [e.response&.code, message.presence || e.message].compact.join(": ") }
rescue StandardError => e
  { "_error" => "#{e.class}: #{e.message}" }
end

scope = tenant.habitations
              .includes(:proprietor)
              .where("COALESCE(NULLIF(vista_codigo, ''), codigo) ~ ?", "^[0-9]+$")
              .where("COALESCE(imovel_dwv, '') <> 'Sim'")
              .order(Arel.sql("COALESCE(NULLIF(vista_codigo, ''), codigo)::bigint ASC"))

if codes_filter.any?
  scope = scope.where("COALESCE(NULLIF(vista_codigo, ''), codigo) IN (?)", codes_filter.to_a)
end

scope = scope.limit(limit) if limit.positive?
habitations = scope.to_a

proprietors_by_vista_code = tenant.proprietors
                                 .where.not(vista_code: [nil, ""])
                                 .select(:id, :name, :vista_code, :email, :mobile_phone, :phone_primary, :business_phone, :residential_phone)
                                 .group_by { |proprietor| normalize_code(proprietor.vista_code) }

api_by_code = {}
if validate_api
  queue = Queue.new
  habitations.each do |habitation|
    queue << (normalize_code(habitation.vista_codigo).presence || normalize_code(habitation.codigo))
  end

  mutex = Mutex.new
  completed = 0
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  threads = Array.new([workers, habitations.size].min) do
    Thread.new do
      loop do
        codigo = queue.pop(true)
        api = fetch_vista_owner(host, key, codigo)
        mutex.synchronize do
          api_by_code[codigo] = api
          completed += 1
          if completed == 1 || (completed % 100).zero? || completed == habitations.size
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
            rate = completed.positive? ? elapsed / completed : 0
            eta = ((habitations.size - completed) * rate).round
            warn "API Vista #{completed}/#{habitations.size} codigo=#{codigo} eta=#{eta}s"
          end
        end
      rescue ThreadError
        break
      end
    end
  end
  threads.each(&:join)
end

rows = habitations.map do |habitation|
  codigo = normalize_code(habitation.vista_codigo).presence || normalize_code(habitation.codigo)
  api = validate_api ? api_by_code[codigo].to_h : habitation.vista_payload.to_h
  api_error = api["_error"].presence
  vista_owner_code = normalize_code(api["CodigoProprietario"])
  vista_owner_name = api_owner_name(api)
  vista_owner_data = owner_data(api)

  current = habitation.proprietor
  current_code = normalize_code(current&.vista_code)
  denorm_code = normalize_code(habitation.proprietario_codigo)
  target_candidates = proprietors_by_vista_code[vista_owner_code].to_a
  target = target_candidates.one? ? target_candidates.first : nil

  action =
    if api_error.present?
      "manual_review_api_error"
    elsif vista_owner_code.blank? || vista_owner_code == "0"
      "manual_review_without_vista_owner"
    elsif target_candidates.empty?
      "create_proprietor_from_vista_and_relink"
    elsif target_candidates.many?
      "manual_review_duplicate_proprietor_vista_code"
    elsif current&.id != target.id
      "relink_habitation_to_existing_proprietor"
    elsif normalize_text(habitation.proprietario) != normalize_text(vista_owner_name) ||
          denorm_code != vista_owner_code
      "legacy_habitation_owner_fields_stale"
    else
      "ok"
    end

  {
    action: action,
    habitation_id: habitation.id,
    codigo: habitation.codigo,
    vista_codigo: habitation.vista_codigo,
    titulo_anuncio: habitation.titulo_anuncio,
    current_proprietor_id: current&.id,
    current_proprietor_name: current&.name,
    current_proprietor_vista_code: current_code,
    legacy_owner_name: habitation.proprietario,
    legacy_owner_code: denorm_code,
    vista_owner_name: vista_owner_name,
    vista_owner_code: vista_owner_code,
    vista_owner_email: vista_owner_data["Email"].presence || vista_owner_data["EmailResidencial"].presence,
    vista_owner_mobile: vista_owner_data["Celular"],
    vista_owner_business_phone: vista_owner_data["FoneComercial"],
    vista_owner_residential_phone: vista_owner_data["FoneResidencial"],
    target_proprietor_id: target&.id,
    target_proprietor_name: target&.name,
    target_proprietor_vista_code: target&.vista_code,
    target_candidates_count: target_candidates.size,
    target_candidate_ids: target_candidates.map(&:id).join("|"),
    api_error: api_error,
    last_sync_at: habitation.last_sync_at,
    updated_at: habitation.updated_at
  }
end

local_only_scope = tenant.habitations
                         .includes(:proprietor)
                         .where("NOT (COALESCE(NULLIF(vista_codigo, ''), codigo) ~ ?)", "^[0-9]+$")
                         .where("NULLIF(TRIM(COALESCE(proprietario, '')), '') IS NOT NULL")

local_only_rows = local_only_scope.map do |habitation|
  current = habitation.proprietor
  {
    action: current.present? ? "local_only_check_relation" : "local_only_create_proprietor_from_habitation_fields",
    habitation_id: habitation.id,
    codigo: habitation.codigo,
    vista_codigo: habitation.vista_codigo,
    titulo_anuncio: habitation.titulo_anuncio,
    current_proprietor_id: current&.id,
    current_proprietor_name: current&.name,
    current_proprietor_vista_code: current&.vista_code,
    legacy_owner_name: habitation.proprietario,
    legacy_owner_code: normalize_code(habitation.proprietario_codigo),
    vista_owner_name: nil,
    vista_owner_code: nil,
    vista_owner_email: nil,
    vista_owner_mobile: nil,
    vista_owner_business_phone: nil,
    vista_owner_residential_phone: nil,
    target_proprietor_id: nil,
    target_proprietor_name: nil,
    target_proprietor_vista_code: nil,
    target_candidates_count: 0,
    target_candidate_ids: nil,
    api_error: nil,
    last_sync_at: habitation.last_sync_at,
    updated_at: habitation.updated_at
  }
end

all_rows = rows + local_only_rows
headers = all_rows.flat_map(&:keys).uniq
all_csv = File.join(output_dir, "owner_impact_all.csv")
impacted_csv = File.join(output_dir, "owner_impact_impacted.csv")
summary_json = File.join(output_dir, "owner_impact_summary.json")

CSV.open(all_csv, "w", write_headers: true, headers: headers) do |csv|
  all_rows.each { |row| csv << headers.map { |key| row[key] } }
end

impacted_rows = all_rows.reject { |row| row[:action] == "ok" }
CSV.open(impacted_csv, "w", write_headers: true, headers: headers) do |csv|
  impacted_rows.each { |row| csv << headers.map { |key| row[key] } }
end

summary = {
  generated_at: Time.current.iso8601,
  tenant_id: tenant.id,
  tenant_name: tenant.name,
  validate_api: validate_api,
  workers: workers,
  scanned_vista_candidates: rows.size,
  scanned_local_only_candidates: local_only_rows.size,
  total_rows: all_rows.size,
  impacted_rows: impacted_rows.size,
  counts_by_action: all_rows.group_by { |row| row[:action] }.transform_values(&:size).sort.to_h,
  output_dir: output_dir,
  files: {
    all_csv: all_csv,
    impacted_csv: impacted_csv,
    summary_json: summary_json
  }
}

File.write(summary_json, JSON.pretty_generate(summary))
puts JSON.pretty_generate(summary)
