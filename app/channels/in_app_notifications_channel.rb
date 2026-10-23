class InAppNotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from InAppNotification.stream_name(current_admin_user.id)
    stream_from "unread_title:#{current_admin_user.tenant_id}"
  end
end
