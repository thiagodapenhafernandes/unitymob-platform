# frozen_string_literal: true

module Admin
  module Field
    class AuditLogsController < Admin::BaseController
      before_action -> { check_permission!(:view, :field_audit) }

      def index
        scope = CheckinAuditLog.order(created_at: :desc)
                               .includes(:admin_user, :actor_admin_user, check_in: :store)

        scope = scope.where(action: params[:action_filter]) if params[:action_filter].present?
        scope = scope.where(admin_user_id: params[:admin_user_id]) if params[:admin_user_id].present?
        scope = scope.joins(:admin_user).where(admin_users: { profile_id: params[:profile_id] }) if params[:profile_id].present?
        scope = scope.where(actor_admin_user_id: params[:actor_admin_user_id]) if params[:actor_admin_user_id].present?
        scope = scope.joins(:check_in).where(check_ins: { store_id: params[:store_id] }) if params[:store_id].present?
        scope = scope.where(ip: params[:ip]) if params[:ip].present?
        scope = scope.where("created_at >= ?", parse_date(params[:start_date]).beginning_of_day) if parse_date(params[:start_date])
        scope = scope.where("created_at <= ?", parse_date(params[:end_date]).end_of_day) if parse_date(params[:end_date])

        @logs = scope.paginate(page: params[:page], per_page: 40)

        # Stats — computadas sobre a mesma janela de filtros (sem paginação)
        stats_scope = scope.except(:order).except(:limit)
        @total_events        = stats_scope.count
        @events_by_action    = stats_scope.group(:action).count
        @events_today        = CheckinAuditLog.where(created_at: Date.current.beginning_of_day..).count
        @events_last_7_days  = CheckinAuditLog.where(created_at: 7.days.ago..).count
        @flagged_count       = CheckinAuditLog.where(action: "flagged_suspicious").count
        @forced_count        = CheckinAuditLog.where(action: "forced_closed").count

        # Para os filtros
        @available_actions = CheckinAuditLog::ACTIONS
        @available_users   = AdminUser.order(:name)
        @available_actors  = AdminUser.where(id: CheckinAuditLog.distinct.pluck(:actor_admin_user_id).compact).order(:name)
        @available_profiles = Profile.order(:name)
        @available_stores = Store.order(:name)
      end

      def show
        @log = CheckinAuditLog.find(params[:id])
      end

      private

      def parse_date(str)
        return if str.blank?

        Date.parse(str.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
