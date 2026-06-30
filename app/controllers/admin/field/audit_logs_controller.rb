# frozen_string_literal: true

module Admin
  module Field
    class AuditLogsController < Admin::BaseController
      before_action -> { check_permission!(:view, :field_audit) }

      def index
        scope = current_tenant.checkin_audit_logs.order(created_at: :desc)
                               .includes(:admin_user, :actor_admin_user, check_in: :store)
        scoped_admin_user_ids = accessible_owner_ids(:field_audit)
        scope = scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids

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
        scoped_stats_scope = current_tenant.checkin_audit_logs
        scoped_stats_scope = scoped_stats_scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids
        @events_today        = scoped_stats_scope.where(created_at: Date.current.beginning_of_day..).count
        @events_last_7_days  = scoped_stats_scope.where(created_at: 7.days.ago..).count
        @flagged_count       = scoped_stats_scope.where(action: "flagged_suspicious").count
        @forced_count        = scoped_stats_scope.where(action: "forced_closed").count

        # Para os filtros
        @available_actions = CheckinAuditLog::ACTIONS
        @available_users   = scoped_admin_users(scoped_admin_user_ids).order(:name)
        @available_actors  = current_tenant.admin_users.account_members
          .where(id: scoped_stats_scope.where.not(actor_admin_user_id: nil).select(:actor_admin_user_id))
          .order(:name)
        @available_profiles = current_tenant.profiles
          .where(id: @available_users.reselect(:profile_id))
          .order(:name)
        @available_stores = current_tenant.stores.order(:name)
      end

      def show
        @log = current_tenant.checkin_audit_logs.find(params[:id])
        return if owner_in_scope?(:field_audit, @log.admin_user_id)

        redirect_to admin_field_audit_logs_path, alert: "Você não tem permissão para acessar este registro de auditoria."
      end

      private

      def parse_date(str)
        return if str.blank?

        Date.parse(str.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def scoped_admin_users(scoped_admin_user_ids)
        users = current_tenant.admin_users.account_members
        scoped_admin_user_ids ? users.where(id: scoped_admin_user_ids) : users
      end
    end
  end
end
