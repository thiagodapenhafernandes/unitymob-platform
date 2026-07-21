require "csv"
require "fileutils"
require "json"

csv_path = ENV.fetch("CSV_PATH") do
  latest = Dir[Rails.root.join("tmp", "owner_audit", "*", "owner_impact_impacted.csv")]
           .select { |path| File.file?(path) }
           .max_by { |path| File.mtime(path) }
  latest || raise("CSV_PATH obrigatório: nenhum owner_impact_impacted.csv encontrado")
end

tenant_id = ENV["TENANT_ID"].presence
tenant = tenant_id.present? ? Tenant.find(tenant_id) : Tenant.default
Current.tenant = tenant if defined?(Current)

dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
sync_legacy_contacts = ActiveModel::Type::Boolean.new.cast(ENV.fetch("SYNC_LEGACY_CONTACTS", "false"))
allowed_actions = %w[
  create_proprietor_from_vista_and_relink
  relink_habitation_to_existing_proprietor
  legacy_habitation_owner_fields_stale
].freeze

timestamp = "#{Time.current.strftime("%Y%m%d_%H%M%S")}_#{Process.pid}"
output_dir = ENV.fetch("OUTPUT_DIR", Rails.root.join("tmp", "owner_audit", "apply_#{timestamp}").to_s)
FileUtils.mkdir_p(output_dir)
report_path = File.join(output_dir, "owner_backfill_apply_report.csv")

def blank_to_nil(value)
  value.to_s.strip.presence
end

def phone_value(row, *keys)
  raw = keys.lazy.map { |key| blank_to_nil(row[key]) }.find(&:present?)
  return if raw.blank?

  Phones::Normalizer.call(raw).presence || raw
end

def proprietor_attrs_from(row)
  {
    name: blank_to_nil(row["vista_owner_name"]) || "Proprietário #{row.fetch("vista_owner_code")}",
    vista_code: blank_to_nil(row["vista_owner_code"]),
    email: blank_to_nil(row["vista_owner_email"]),
    mobile_phone: phone_value(row, "vista_owner_mobile"),
    business_phone: phone_value(row, "vista_owner_business_phone"),
    residential_phone: phone_value(row, "vista_owner_residential_phone"),
    role: :owner
  }.compact
end

def sync_habitation_attrs_from(proprietor, sync_legacy_contacts:)
  attrs = {
    proprietor_id: proprietor.id,
    proprietario: proprietor.name,
    proprietario_codigo: proprietor.vista_code
  }

  if sync_legacy_contacts
    attrs.merge!(
      proprietario_email: proprietor.email,
      proprietario_celular: proprietor.mobile_phone.presence || proprietor.phone_primary,
      proprietario_telefone_comercial: proprietor.business_phone,
      proprietario_telefone_residencial: proprietor.residential_phone
    )
  end

  attrs.merge(updated_at: Time.current)
end

def changed_attributes_for(record, attrs)
  attrs.except(:updated_at).select do |key, value|
    record.public_send(key) != value
  end
end

rows = CSV.read(csv_path, headers: true)
report_rows = []
stats = Hash.new(0)

rows.each do |row|
  action = row["action"].to_s
  unless allowed_actions.include?(action)
    stats[:skipped_manual] += 1
    next
  end

  habitation = tenant.habitations.find_by(id: row["habitation_id"])
  unless habitation
    stats[:missing_habitation] += 1
    report_rows << row.to_h.merge("apply_status" => "missing_habitation", "apply_error" => nil)
    next
  end

  owner_code = blank_to_nil(row["vista_owner_code"])
  if owner_code.blank? || owner_code == "0"
    stats[:skipped_invalid_owner_code] += 1
    report_rows << row.to_h.merge("apply_status" => "skipped_invalid_owner_code", "apply_error" => nil)
    next
  end

  candidates = tenant.proprietors.where(vista_code: owner_code).order(:id).to_a
  if candidates.many?
    stats[:skipped_duplicate_owner_code] += 1
    report_rows << row.to_h.merge("apply_status" => "skipped_duplicate_owner_code", "apply_error" => nil)
    next
  end

  proprietor = candidates.first || tenant.proprietors.new(tenant: tenant)
  before = {
    habitation_proprietor_id: habitation.proprietor_id,
    habitation_proprietor_name: habitation.proprietor&.name,
    habitation_legacy_owner_name: habitation.proprietario,
    habitation_legacy_owner_code: habitation.proprietario_codigo,
    proprietor_id: proprietor.persisted? ? proprietor.id : nil,
    proprietor_name: proprietor.name,
    proprietor_vista_code: proprietor.vista_code
  }

  attrs = proprietor_attrs_from(row)
  proprietor.assign_attributes(attrs)
  proprietor_changes = proprietor.changes
  habitation_attrs = sync_habitation_attrs_from(proprietor, sync_legacy_contacts: sync_legacy_contacts)
  habitation_changes = proprietor.persisted? ? changed_attributes_for(habitation, habitation_attrs) : { proprietor_id: nil }

  if proprietor.persisted? && proprietor_changes.blank? && habitation_changes.blank?
    stats[:already_consistent] += 1
    report_rows << row.to_h.merge(
      "apply_status" => "already_consistent",
      "apply_error" => nil,
      "before" => before.to_json,
      "after" => {
        proprietor_id: proprietor.id,
        proprietor_name: proprietor.name,
        proprietor_vista_code: proprietor.vista_code,
        habitation_proprietor_id: habitation.proprietor_id
      }.to_json
    )
    next
  end

  if dry_run
    status = if proprietor.new_record?
               "would_create_and_relink"
             elsif habitation_changes.key?(:proprietor_id)
               "would_relink"
             else
               "would_update"
             end
    stats[status.to_sym] += 1
    report_rows << row.to_h.merge(
      "apply_status" => status,
      "apply_error" => nil,
      "before" => before.to_json,
      "after" => {
        proprietor_attrs: attrs,
        proprietor_changes: proprietor_changes,
        habitation_attrs: habitation_attrs.except(:updated_at),
        habitation_changes: habitation_changes
      }.to_json
    )
    next
  end

  Habitation.transaction do
    proprietor.save!
    habitation_attrs = sync_habitation_attrs_from(proprietor, sync_legacy_contacts: sync_legacy_contacts)
    habitation.update_columns(habitation_attrs)
  end

  status = if before[:proprietor_id].blank?
             "created_and_relinked"
           elsif before[:habitation_proprietor_id] != proprietor.id
             "relinked"
           else
             "updated"
           end
  stats[status.to_sym] += 1
  report_rows << row.to_h.merge(
    "apply_status" => status,
    "apply_error" => nil,
    "before" => before.to_json,
    "after" => {
      proprietor_id: proprietor.id,
      proprietor_name: proprietor.name,
      proprietor_vista_code: proprietor.vista_code,
      habitation_proprietor_id: habitation.reload.proprietor_id
    }.to_json
  )
rescue StandardError => e
  stats[:failed] += 1
  report_rows << row.to_h.merge("apply_status" => "failed", "apply_error" => "#{e.class}: #{e.message}")
end

headers = report_rows.flat_map(&:keys).uniq
CSV.open(report_path, "w", write_headers: true, headers: headers) do |csv|
  report_rows.each { |report_row| csv << headers.map { |key| report_row[key] } }
end

verification = nil
unless dry_run
  verifiable_rows = rows.select do |row|
    allowed_actions.include?(row["action"].to_s) &&
      blank_to_nil(row["vista_owner_code"]).present? &&
      blank_to_nil(row["vista_owner_code"]) != "0"
  end

  failures = verifiable_rows.filter_map do |row|
    habitation = tenant.habitations.includes(:proprietor).find_by(id: row["habitation_id"])
    expected_code = blank_to_nil(row["vista_owner_code"])
    actual_code = habitation&.proprietor&.vista_code.to_s
    next if habitation && actual_code == expected_code

    {
      habitation_id: row["habitation_id"],
      codigo: row["codigo"],
      expected_vista_owner_code: expected_code,
      actual_vista_owner_code: actual_code.presence,
      actual_proprietor_id: habitation&.proprietor_id
    }
  end

  verification = {
    checked: verifiable_rows.size,
    failures: failures.size,
    sample_failures: failures.first(20)
  }
end

summary = {
  generated_at: Time.current.iso8601,
  tenant_id: tenant.id,
  tenant_name: tenant.name,
  dry_run: dry_run,
  sync_legacy_contacts: sync_legacy_contacts,
  csv_path: csv_path,
  report_path: report_path,
  stats: stats.sort.to_h,
  verification: verification
}

File.write(File.join(output_dir, "owner_backfill_apply_summary.json"), JSON.pretty_generate(summary))
puts JSON.pretty_generate(summary)
