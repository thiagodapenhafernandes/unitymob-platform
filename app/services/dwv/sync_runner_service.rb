require "set"

module Dwv
  class SyncRunnerService
    DEFAULT_LIMIT = 50
    DEFAULT_MAX_PAGES = 100
    DEFAULT_BASE_URL = "https://agencies.dwvapp.com.br".freeze
    DEFAULT_REQUEST_PAUSE_SECONDS = 0.70
    MAX_LIMIT = 50
    MAX_PAGES = 100

    def initialize(tenant: nil)
      @tenant = tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para Dwv::SyncRunnerService" if @tenant.blank?
    end

    def call(mode: "full", limit: nil, max_pages: nil, status_service: nil, last_updates: nil)
      ensure_enabled_and_token!
      @status_service = status_service

      normalized_limit = normalize_limit(limit || Setting.get("dwv_sync_limit", DEFAULT_LIMIT))
      normalized_max_pages = normalize_max_pages(max_pages || Setting.get("dwv_sync_max_pages", DEFAULT_MAX_PAGES))
      normalized_last_updates = normalize_last_updates(last_updates)
      @status_service&.mark_processing!(
        mode: mode,
        message: "Sincronização DWV iniciada (modo: #{mode}).",
        progress: 3
      )

      case mode.to_s
      when "full"
        sync_active_properties(limit: normalized_limit, max_pages: normalized_max_pages, deactivate_removed: true)
      when "batch"
        sync_active_properties(limit: normalized_limit, max_pages: normalized_max_pages, deactivate_removed: false)
      when "incremental"
        sync_incremental_properties(limit: normalized_limit, max_pages: normalized_max_pages, last_updates: normalized_last_updates)
      when "deactivate_removed"
        { imported: 0, deactivated: deactivate_removed_properties(limit: normalized_limit, max_pages: normalized_max_pages), errors_count: 0 }
      else
        raise ArgumentError, "Modo de sincronização DWV inválido: #{mode}"
      end
    end

    private

    attr_reader :tenant

    def sync_incremental_properties(limit:, max_pages:, last_updates:)
      client = build_client
      imported = 0
      errors_count = 0
      errors_by_reason = Hash.new(0)
      filters = { last_updates: last_updates }
      active_ids = collect_active_property_ids(client, limit: limit, max_pages: max_pages, filters: filters)
      removed_ids = collect_removed_property_ids(client, limit: limit, max_pages: max_pages, filters: filters)
      total_steps = active_ids.size + removed_ids.size
      processed_steps = 0

      if total_steps.zero?
        @status_service&.update_progress!(progress: 100, message: "Sincronização DWV incremental sem imóveis alterados em #{last_updates}.")
      end

      active_ids.each do |property_id|
        begin
          details = client.property_details(property_id)
          Dwv::PropertyImportService.new(details, tenant: tenant).perform
          imported += 1
        rescue => e
          errors_count += 1
          errors_by_reason[normalize_error_message(e.message)] += 1
          Rails.logger.error("[DWV] Falha ao importar incremental property_id=#{property_id}: #{e.message}")
        ensure
          processed_steps += 1
          publish_progress(processed_steps, total_steps, "Importando alterações DWV de #{last_updates} (#{processed_steps}/#{total_steps})...")
          pause_if_needed
        end
      end

      deactivated = deactivate_removed_properties_by_ids(removed_ids)
      processed_steps += removed_ids.size
      publish_progress(processed_steps, total_steps, "Sincronização DWV incremental concluída.")

      {
        imported: imported,
        deactivated: deactivated,
        errors_count: errors_count,
        errors_by_reason: errors_by_reason.sort_by { |_, count| -count }.to_h
      }
    end

    def sync_active_properties(limit:, max_pages:, deactivate_removed:)
      client = build_client
      imported = 0
      errors_count = 0
      errors_by_reason = Hash.new(0)
      active_ids = collect_active_property_ids(client, limit: limit, max_pages: max_pages)
      removed_ids = if deactivate_removed
        (collect_removed_property_ids(client, limit: limit, max_pages: max_pages) + local_dwv_ids_missing_from(active_ids)).uniq
      else
        []
      end
      total_steps = active_ids.size + removed_ids.size
      processed_steps = 0

      if total_steps.zero?
        @status_service&.update_progress!(progress: 100, message: "Sincronização DWV finalizada sem imóveis para processar.")
      end

      active_ids.each do |property_id|
        begin
          details = client.property_details(property_id)
          Dwv::PropertyImportService.new(details, tenant: tenant).perform
          imported += 1
        rescue => e
          errors_count += 1
          errors_by_reason[normalize_error_message(e.message)] += 1
          Rails.logger.error("[DWV] Falha ao importar property_id=#{property_id}: #{e.message}")
        ensure
          processed_steps += 1
          publish_progress(processed_steps, total_steps, "Importando imóveis DWV (#{processed_steps}/#{total_steps})...")
          pause_if_needed
        end
      end

      deactivated = deactivate_removed ? deactivate_removed_properties_by_ids(removed_ids) : 0
      processed_steps += removed_ids.size
      publish_progress(processed_steps, total_steps, "Desativação de removidos concluída.")

      {
        imported: imported,
        deactivated: deactivated,
        errors_count: errors_count,
        errors_by_reason: errors_by_reason.sort_by { |_, count| -count }.to_h
      }
    end

    def deactivate_removed_properties(limit:, max_pages:, client: nil)
      client ||= build_client
      removed_ids = collect_removed_property_ids(client, limit: limit, max_pages: max_pages)
      return 0 if removed_ids.empty?

      @status_service&.update_progress!(progress: 40, message: "Aplicando desativação de removidos DWV...")
      result = deactivate_removed_properties_by_ids(removed_ids)
      @status_service&.update_progress!(progress: 100, message: "Desativação de removidos DWV concluída.")
      result
    end

    def deactivate_removed_properties_by_ids(removed_ids)
      return 0 if removed_ids.empty?

      tenant.habitations.where(codigo_dwv: removed_ids).update_all(
        exibir_no_site_flag: false,
        last_sync_at: Time.current,
        last_sync_status: "inactive",
        last_sync_message: "Despublicado localmente por status removido na DWV"
      )
    end

    def local_dwv_ids_missing_from(active_ids)
      active_ids = active_ids.map(&:to_s)
      scope = tenant.habitations.where(imovel_dwv: "Sim").where.not(codigo_dwv: [nil, ""])
      scope = active_ids.any? ? scope.where.not(codigo_dwv: active_ids) : scope
      scope.distinct.pluck(:codigo_dwv)
    end

    def collect_active_property_ids(client, limit:, max_pages:, filters: {})
      collect_property_ids(client, deleted: false, limit: limit, max_pages: max_pages, filters: filters, state: :active)
    end

    def collect_removed_property_ids(client, limit:, max_pages:, filters: {})
      ids = collect_property_ids(client, deleted: true, limit: limit, max_pages: max_pages, filters: filters, state: :removed)
      inactive_ids = collect_property_ids(client, deleted: false, limit: limit, max_pages: max_pages, filters: filters, state: :removed)
      (ids + inactive_ids).uniq
    end

    def collect_property_ids(client, deleted:, limit:, max_pages:, filters: {}, state: nil)
      ids = Set.new

      (1..max_pages).each do |page|
        response = client.list_properties(limit: limit, page: page, deleted: deleted, **filters)
        collection = Dwv::PropertyImportService.extract_collection(response)
        break if collection.blank?

        collection.each do |item|
          next if state == :active && removed_property_item?(item)
          next if state == :removed && !removed_property_item?(item)

          property_id = Dwv::PropertyImportService.extract_property_id(item).to_s.strip
          next if property_id.blank?

          ids << property_id
        end

        break if collection.size < limit
      end

      ids.to_a
    end

    def removed_property_item?(item)
      return false unless item.is_a?(Hash)

      deleted = item["deleted"] || item[:deleted]
      status = (item["status"] || item[:status] || item["integration_status"] || item[:integration_status]).to_s.strip.downcase

      deleted == true ||
        deleted.to_s == "true" ||
        status == "inactive" ||
        status == "auto_inactive"
    end

    def normalize_limit(raw)
      value = raw.to_i
      value = DEFAULT_LIMIT if value <= 0
      [value, MAX_LIMIT].min
    end

    def normalize_max_pages(raw)
      value = raw.to_i
      value = DEFAULT_MAX_PAGES if value <= 0
      [value, MAX_PAGES].min
    end

    def normalize_last_updates(raw)
      value = raw.to_s.strip
      return iso_date_range(Time.zone.today, Time.zone.today) if value.blank?

      dates = value.split(",").map { |date| parse_last_update_date(date) }.compact
      return value if dates.empty?

      iso_date_range(dates.first, dates.second || dates.first)
    end

    def parse_last_update_date(raw)
      value = raw.to_s.strip
      return if value.blank?

      Date.iso8601(value)
    rescue Date::Error
      begin
        Date.strptime(value, "%d/%m/%Y")
      rescue Date::Error
        nil
      end
    end

    def iso_date_range(start_date, end_date)
      "#{start_date.iso8601},#{end_date.iso8601}"
    end

    def pause_if_needed
      pause_seconds = request_pause_seconds
      return unless pause_seconds.positive?

      sleep(pause_seconds)
    end

    def build_client
      Dwv::Client.new(
        token: Setting.get("dwv_api_token"),
        base_url: Setting.get("dwv_base_url", DEFAULT_BASE_URL)
      )
    end

    def ensure_enabled_and_token!
      enabled = Setting.get("dwv_enabled", "false") == "true"
      token = Setting.get("dwv_api_token").to_s

      raise "Integração DWV desativada." unless enabled
      raise "Token DWV não configurado." if token.blank?
    end

    def publish_progress(processed, total, message)
      return if total.to_i <= 0

      percentage = ((processed.to_f / total.to_f) * 100).round
      percentage = 1 if processed.to_i.positive? && percentage.zero?
      @status_service&.update_progress!(progress: percentage, message: message)
    end

    def request_pause_seconds
      from_setting = Setting.get("dwv_request_pause_seconds").to_s
      value = if from_setting.present?
        from_setting.to_f
      else
        ENV.fetch("DWV_REQUEST_PAUSE_SECONDS", DEFAULT_REQUEST_PAUSE_SECONDS.to_s).to_f
      end

      value.clamp(0.2, 2.0)
    end

    def normalize_error_message(message)
      normalized = message.to_s.strip
      return "Erro desconhecido" if normalized.blank?

      normalized
    end
  end
end
