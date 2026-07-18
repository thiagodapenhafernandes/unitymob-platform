module System
  class PlatformHealthReport
    TRAFFIC_NOISE_EXCEPTIONS = %w[
      ActionController::RoutingError
      ActionController::UnknownFormat
    ].freeze

    def self.call
      new.call
    end

    def call
      {
        release: release_info,
        tenants: tenant_rows,
        errors: error_summary
      }
    end

    private

    def release_info
      {
        identifier: ENV["RELEASE_VERSION"].presence || release_from_path || "development",
        revision: ENV["SOURCE_VERSION"].to_s.first(12).presence,
        schema_version: ActiveRecord::SchemaMigration.order(version: :desc).pick(:version),
        migrations_pending: ActiveRecord::MigrationContext.new(Rails.root.join("db/migrate")).needs_migration?
      }
    rescue StandardError
      { identifier: "desconhecida", revision: nil, schema_version: nil }
    end

    def release_from_path
      Rails.root.to_s[%r{/releases/(\d+)}, 1]&.then { |number| "release #{number}" }
    end

    def tenant_rows
      tenants = Tenant.order(:name).to_a
      ids = tenants.map(&:id)
      user_counts = AdminUser.where(tenant_id: ids).group(:tenant_id).count
      active_user_counts = AdminUser.where(tenant_id: ids, active: true).group(:tenant_id).count
      habitation_counts = Habitation.where(tenant_id: ids).group(:tenant_id).count
      lead_counts = Lead.where(tenant_id: ids).group(:tenant_id).count
      open_error_counts = open_errors.where(tenant_id: ids).group(:tenant_id).count
      portal_counts = PortalIntegration.where(tenant_id: ids, enabled: true).group(:tenant_id).count
      portal_failed_counts = PortalIntegration.where(tenant_id: ids, enabled: true)
        .where("LOWER(COALESCE(operational_status, '')) LIKE '%fail%' OR LOWER(COALESCE(operational_status, '')) LIKE '%error%'")
        .group(:tenant_id).count
      whatsapp_failed_counts = WhatsappBusinessIntegration.where(tenant_id: ids, status: "failed").group(:tenant_id).count
      storage_bytes = habitation_storage_bytes(ids)

      tenants.map do |tenant|
        integration_failures = whatsapp_failed_counts[tenant.id].to_i + portal_failed_counts[tenant.id].to_i
        attention = open_error_counts[tenant.id].to_i + integration_failures
        {
          id: tenant.id,
          name: tenant.name,
          slug: tenant.slug,
          active: tenant.active?,
          users: user_counts[tenant.id].to_i,
          active_users: active_user_counts[tenant.id].to_i,
          habitations: habitation_counts[tenant.id].to_i,
          leads: lead_counts[tenant.id].to_i,
          portals: portal_counts[tenant.id].to_i,
          storage_bytes: storage_bytes[tenant.id].to_i,
          open_errors: open_error_counts[tenant.id].to_i,
          integration_failures: integration_failures,
          status: attention.positive? ? "attention" : (tenant.active? ? "healthy" : "inactive")
        }
      end
    rescue StandardError => error
      Rails.logger.warn("[System::PlatformHealthReport] tenant_rows #{error.class}: #{error.message}")
      []
    end

    def habitation_storage_bytes(tenant_ids)
      normalized_ids = Array(tenant_ids).compact_blank.map(&:to_i).uniq.sort
      return {} if normalized_ids.blank?

      Rails.cache.fetch("system/platform_health_report/storage_bytes/v1/#{normalized_ids.join('-')}", expires_in: 15.minutes) do
        ActiveStorage::Attachment
          .joins("INNER JOIN habitations ON habitations.id = active_storage_attachments.record_id")
          .joins(:blob)
          .where(record_type: "Habitation", habitations: { tenant_id: normalized_ids })
          .group("habitations.tenant_id")
          .sum("active_storage_blobs.byte_size")
      end
    rescue StandardError
      {}
    end

    def error_summary
      return { application_open: 0, traffic_noise_open: 0, unassigned_open: 0, affected_tenants: 0 } unless ErrorEvent.storage_ready?

      unresolved = open_errors
      noise = unresolved.where(exception_class: TRAFFIC_NOISE_EXCEPTIONS)
      application = unresolved.where.not(exception_class: TRAFFIC_NOISE_EXCEPTIONS)
      {
        application_open: application.count,
        traffic_noise_open: noise.count,
        traffic_noise_occurrences: noise.sum(:occurrences_count),
        unassigned_open: application.where(tenant_id: nil).count,
        affected_tenants: application.where.not(tenant_id: nil).distinct.count(:tenant_id)
      }
    rescue StandardError
      { application_open: 0, traffic_noise_open: 0, unassigned_open: 0, affected_tenants: 0 }
    end

    def open_errors
      ErrorEvent.unresolved
    end
  end
end
