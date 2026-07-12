module Admin
  module System
    class HealthController < Admin::BaseController
      before_action :require_system_admin!

      def show
        @health = ::System::HealthSnapshot.call
        @platform = ::System::PlatformHealthReport.call
        @assessment = ::System::HealthAssessment.call(runtime: @health, platform: @platform)
        @history = health_history
        @health_setting = SystemHealthSetting.instance
        @selected_tenant = selected_tenant
        @tenant_history = tenant_history
        @queue = queue_metrics
        @errors = error_metrics
      end


      def update
        setting = SystemHealthSetting.instance
        if setting.update(health_setting_params)
          redirect_to admin_system_health_path(anchor: "thresholds"), notice: "Limites de saúde atualizados com sucesso."
        else
          redirect_to admin_system_health_path(anchor: "thresholds"), alert: setting.errors.full_messages.to_sentence
        end
      end

      private

      def health_history
        return [] unless ActiveRecord::Base.connection.data_source_exists?("system_health_snapshots")

        SystemHealthSnapshot.platform.recent_first.limit(24).to_a.reverse
      rescue ActiveRecord::StatementInvalid
        []
      end

      def selected_tenant
        return if params[:tenant_id].blank?

        Tenant.find_by(id: params[:tenant_id])
      end

      def tenant_history
        return [] if @selected_tenant.blank?
        return [] unless ActiveRecord::Base.connection.data_source_exists?("system_health_snapshots")

        SystemHealthSnapshot.where(tenant_id: @selected_tenant.id).recent_first.limit(48).to_a.reverse
      rescue ActiveRecord::StatementInvalid
        []
      end

      def health_setting_params
        params.require(:system_health_setting).permit(
          :memory_available_warning_percent, :memory_available_critical_percent,
          :disk_warning_percent, :disk_critical_percent, :swap_warning_mb,
          :http_warning_ms, :http_critical_ms, :application_errors_warning,
          :application_errors_critical, :integration_failures_critical
        )
      end

      def queue_metrics
        {
          ready: safe_value { SolidQueue::ReadyExecution.count },
          claimed: safe_value { SolidQueue::ClaimedExecution.count },
          scheduled: safe_value { SolidQueue::ScheduledExecution.count },
          failed: safe_value { SolidQueue::FailedExecution.count },
          processes: safe_value { SolidQueue::Process.where("last_heartbeat_at >= ?", 5.minutes.ago).count },
          oldest_ready_at: safe_value { SolidQueue::ReadyExecution.minimum(:created_at) }
        }
      end

      def error_metrics
        return {} unless ErrorEvent.storage_ready?

        {
          open: ErrorEvent.unresolved.count,
          last_hour: ErrorEvent.where(last_seen_at: 1.hour.ago..).sum(:occurrences_count),
          media_missing: ErrorEvent.unresolved.where(exception_class: "ActiveStorage::FileNotFoundError").sum(:occurrences_count)
        }
      rescue StandardError
        {}
      end

      def safe_value
        yield
      rescue StandardError
        nil
      end
    end
  end
end
