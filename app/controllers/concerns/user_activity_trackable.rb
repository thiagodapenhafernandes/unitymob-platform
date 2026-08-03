module UserActivityTrackable
  extend ActiveSupport::Concern

  private

  def record_user_activity!(event_name, **payload)
    Audit::UserActivityTracker.call(
      tenant: current_tenant,
      admin_user: current_admin_user,
      request: request,
      event_name:,
      **payload
    )
  end
end
