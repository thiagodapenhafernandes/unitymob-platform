require "csv"
require "fileutils"
require "json"
require "set"

tenant_id = ENV["TENANT_ID"].presence
tenant = tenant_id.present? ? Tenant.find(tenant_id) : Tenant.default
Current.tenant = tenant if defined?(Current)

dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
action = ENV.fetch("ACTION", "destroy").to_s
limit = [ENV.fetch("LIMIT", Setting.get("dwv_sync_limit", Dwv::SyncRunnerService::DEFAULT_LIMIT)).to_i, 1].max
limit = [limit, Dwv::SyncRunnerService::MAX_LIMIT].min
max_pages = [ENV.fetch("MAX_PAGES", Setting.get("dwv_sync_max_pages", Dwv::SyncRunnerService::DEFAULT_MAX_PAGES)).to_i, 1].max
max_pages = [max_pages, Dwv::SyncRunnerService::MAX_PAGES].min
timestamp = "#{Time.current.strftime("%Y%m%d_%H%M%S")}_#{Process.pid}"
output_dir = ENV.fetch("OUTPUT_DIR", Rails.root.join("tmp", "dwv_removed_backfill", timestamp).to_s)
FileUtils.mkdir_p(output_dir)

unless action.in?(%w[destroy unpublish])
  raise ArgumentError, "ACTION inválida: use destroy ou unpublish"
end

client = Dwv::Client.new(
  token: Setting.get("dwv_api_token", tenant: tenant),
  base_url: Setting.get("dwv_base_url", Dwv::SyncRunnerService::DEFAULT_BASE_URL, tenant: tenant)
)

def removed_property_item?(item)
  return false unless item.is_a?(Hash)

  deleted = item["deleted"] || item[:deleted]
  status = (item["status"] || item[:status] || item["integration_status"] || item[:integration_status]).to_s.strip.downcase
  deleted == true || deleted.to_s == "true" || status == "inactive" || status == "auto_inactive"
end

def collect_dwv_ids(client, deleted:, limit:, max_pages:, want_removed:)
  ids = Set.new
  rows = []

  (1..max_pages).each do |page|
    response = client.list_properties(limit: limit, page: page, deleted: deleted)
    collection = Dwv::PropertyImportService.extract_collection(response)
    break if collection.blank?

    collection.each do |item|
      removed = removed_property_item?(item)
      next if want_removed != removed

      id = Dwv::PropertyImportService.extract_property_id(item).to_s.strip
      next if id.blank?

      ids << id
      rows << {
        dwv_id: id,
        deleted: item["deleted"] || item[:deleted],
        status: item["status"] || item[:status],
        integration_status: item["integration_status"] || item[:integration_status],
        title: item["title"] || item[:title],
        last_updated_at: item["last_updated_at"] || item[:last_updated_at]
      }
    end

    break if collection.size < limit
  end

  [ids.to_a, rows]
end

active_ids, active_api_rows = collect_dwv_ids(client, deleted: false, limit: limit, max_pages: max_pages, want_removed: false)
removed_deleted_ids, removed_deleted_api_rows = collect_dwv_ids(client, deleted: true, limit: limit, max_pages: max_pages, want_removed: true)
removed_inactive_ids, removed_inactive_api_rows = collect_dwv_ids(client, deleted: false, limit: limit, max_pages: max_pages, want_removed: true)
removed_api_ids = (removed_deleted_ids + removed_inactive_ids).uniq

local_dwv_scope = tenant.habitations.where(imovel_dwv: "Sim").where.not(codigo_dwv: [nil, ""])
missing_local_ids = local_dwv_scope.where.not(codigo_dwv: active_ids).where.not(codigo_dwv: removed_api_ids).distinct.pluck(:codigo_dwv)
candidate_dwv_ids = (removed_api_ids + missing_local_ids).uniq
candidates = local_dwv_scope.where(codigo_dwv: candidate_dwv_ids).order(:id).to_a

report_rows = []
stats = Hash.new(0)

candidates.each do |habitation|
  reason = if removed_api_ids.include?(habitation.codigo_dwv.to_s)
             "dwv_removed_or_inactive"
           else
             "missing_from_active_dwv_list"
           end
  before = {
    id: habitation.id,
    codigo: habitation.codigo,
    codigo_dwv: habitation.codigo_dwv,
    status: habitation.status,
    exibir_no_site_flag: habitation.exibir_no_site_flag,
    last_sync_status: habitation.last_sync_status,
    updated_at: habitation.updated_at
  }

  if dry_run
    stats["would_#{action}"] += 1
    report_rows << before.merge(reason: reason, action: action, apply_status: "dry_run", error: nil)
    next
  end

  case action
  when "unpublish"
    now = Time.current
    habitation.update_columns(
      exibir_no_site_flag: false,
      last_sync_at: now,
      last_sync_status: "inactive",
      last_sync_message: "Removido da pauta DWV por backfill",
      updated_at: now
    )
    stats[:unpublished] += 1
    report_rows << before.merge(reason: reason, action: action, apply_status: "unpublished", error: nil)
  when "destroy"
    habitation.destroy!
    stats[:destroyed] += 1
    report_rows << before.merge(reason: reason, action: action, apply_status: "destroyed", error: nil)
  end
rescue StandardError => e
  stats[:failed] += 1
  report_rows << before.merge(reason: reason, action: action, apply_status: "failed", error: "#{e.class}: #{e.message}")
end

report_path = File.join(output_dir, "dwv_removed_backfill_report.csv")
headers = report_rows.flat_map(&:keys).uniq
CSV.open(report_path, "w", write_headers: true, headers: headers) do |csv|
  report_rows.each { |row| csv << headers.map { |key| row[key] } }
end

api_snapshot_path = File.join(output_dir, "dwv_api_snapshot.json")
File.write(
  api_snapshot_path,
  JSON.pretty_generate(
    active: active_api_rows,
    removed_deleted: removed_deleted_api_rows,
    removed_inactive: removed_inactive_api_rows
  )
)

verification = nil
unless dry_run
  remaining = tenant.habitations.where(imovel_dwv: "Sim", codigo_dwv: candidate_dwv_ids)
  verification = {
    remaining_candidate_rows: remaining.count,
    remaining_published_candidate_rows: remaining.where(exibir_no_site_flag: true).count,
    sample_remaining: remaining.order(:id).limit(20).pluck(:id, :codigo, :codigo_dwv, :status, :exibir_no_site_flag, :last_sync_status)
  }
end

summary = {
  generated_at: Time.current.iso8601,
  tenant_id: tenant.id,
  tenant_name: tenant.name,
  dry_run: dry_run,
  action: action,
  limit: limit,
  max_pages: max_pages,
  active_api_ids: active_ids.size,
  removed_api_ids: removed_api_ids.size,
  missing_local_ids: missing_local_ids.size,
  candidate_rows: candidates.size,
  stats: stats.sort.to_h,
  verification: verification,
  output_dir: output_dir,
  report_path: report_path,
  api_snapshot_path: api_snapshot_path
}

File.write(File.join(output_dir, "dwv_removed_backfill_summary.json"), JSON.pretty_generate(summary))
puts JSON.pretty_generate(summary)
