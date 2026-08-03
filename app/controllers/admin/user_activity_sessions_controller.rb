class Admin::UserActivitySessionsController < Admin::BaseController
  before_action :require_admin!

  def index
    scope = current_tenant.operational_user_sessions.includes(:admin_user).recent
    scope = scope.where(admin_user_id: params[:admin_user_id]) if params[:admin_user_id].present?
    scope = scope.where(device_type: params[:device_type]) if params[:device_type].present?
    scope = scope.where("started_at >= ?", parsed_date(params[:start_date]).beginning_of_day) if parsed_date(params[:start_date])
    scope = scope.where("started_at <= ?", parsed_date(params[:end_date]).end_of_day) if parsed_date(params[:end_date])

    if params[:event_name].present?
      scope = scope.where(id: current_tenant.operational_user_events.where(name: params[:event_name]).select(:operational_user_session_id))
    end

    stats_scope = scope.except(:order, :limit, :offset)
    stats_events = current_tenant.operational_user_events.where(operational_user_session_id: stats_scope.select(:id))
    @total_sessions = stats_scope.count
    @total_duration_seconds = stats_scope.sum(:duration_seconds)
    @total_searches = stats_events.searches.count
    @total_property_views = stats_events.property_views.count
    @total_shared = stats_events.where(name: "selection_shared").count
    @active_sessions = stats_scope.active_since(30.minutes.ago).count

    @sessions = scope.paginate(page: params[:page], per_page: 30)
    session_ids = @sessions.map(&:id)
    @session_event_counts = current_tenant.operational_user_events
      .where(operational_user_session_id: session_ids)
      .group(:operational_user_session_id, :name)
      .count
    @session_visible_counts = visible_habitation_counts_for(session_ids)

    @available_users = current_tenant.admin_users.account_members.order(:name)
    @available_device_types = current_tenant.operational_user_sessions.where.not(device_type: [nil, ""]).distinct.order(:device_type).pluck(:device_type)
  end

  def show
    @session = current_tenant.operational_user_sessions.includes(:admin_user).find(params[:id])
    @events = @session.events.includes(:habitation).recent.paginate(page: params[:page], per_page: 80)
    @event_counts = @session.events.group(:name).count
    @search_events = @session.events.searches.recent.limit(20)
    @opened_properties = @session.events.property_views.includes(:habitation).recent.limit(40)
    @visible_habitation_count = visible_habitation_counts_for([@session.id])[@session.id].to_i
  end

  private

  def parsed_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def visible_habitation_counts_for(session_ids)
    return {} if session_ids.blank?

    current_tenant.operational_user_events
      .where(operational_user_session_id: session_ids)
      .pluck(:operational_user_session_id, :visible_habitation_ids)
      .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(session_id, habitation_ids), memo|
        Array(habitation_ids).each do |habitation_id|
          parsed_id = Integer(habitation_id, exception: false)
          memo[session_id] << parsed_id if parsed_id
        end
      end
      .transform_values { |habitation_ids| habitation_ids.uniq.size }
  end
end
