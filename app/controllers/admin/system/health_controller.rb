module Admin
  module System
    class HealthController < Admin::BaseController
      before_action :require_system_admin!

      def show
        @health = ::System::HealthSnapshot.call
        @platform = ::System::PlatformHealthReport.call
        @assessment = ::System::HealthAssessment.call(runtime: @health, platform: @platform)
        @history = health_history
        @queue = queue_metrics
        @errors = error_metrics
      end

      private

      def health_history
        return [] unless ActiveRecord::Base.connection.data_source_exists?("system_health_snapshots")

        SystemHealthSnapshot.platform.recent_first.limit(24).to_a.reverse
      rescue ActiveRecord::StatementInvalid
        []
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
