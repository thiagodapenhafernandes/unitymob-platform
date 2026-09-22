class InAppNotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from InAppNotification.stream_name(current_admin_user.id)
  end
end
