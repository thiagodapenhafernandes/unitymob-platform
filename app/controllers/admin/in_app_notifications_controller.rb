class Admin::InAppNotificationsController < Admin::BaseController
  def read
    notifications.where(id: params[:id]).update_all(read_at: Time.current, updated_at: Time.current)
    render json: { unread_count: unread_count }
  end

  def read_all
    notifications.unread.update_all(read_at: Time.current, updated_at: Time.current)
    render json: { unread_count: 0 }
  end

  private

  def notifications
    InAppNotification.where(admin_user_id: current_admin_user.id)
  end

  def unread_count
    InAppNotification.unread_count_for(current_admin_user)
  end
end
