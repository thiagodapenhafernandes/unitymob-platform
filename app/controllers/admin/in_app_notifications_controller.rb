class Admin::InAppNotificationsController < Admin::BaseController
  def summary
    render json: { total: InAppNotification.title_count_for(current_admin_user, current_tenant), unread_count: unread_count }
  end

  def read_direct
    return head :forbidden unless current_admin_user.can?(:view, :leads)

    lead = Lead.accessible_to_admin(current_admin_user, tenant: current_tenant).find(params[:lead_id])
    scope = notifications.unread.where(kind: "instagram_message").where("metadata ->> 'lead_id' = ?", lead.id.to_s)
    scope = scope.where("(metadata ->> 'instagram_message_id')::bigint <= ?", params[:cursor].to_i)
    scope.update_all(read_at: Time.current, updated_at: Time.current)
    InAppNotification.broadcast_event!(current_admin_user.id, event: "unread_changed")
    head :no_content
  end

  def read
    notifications.where(id: params[:id]).update_all(read_at: Time.current, updated_at: Time.current)
    InAppNotification.broadcast_event!(current_admin_user.id, event: "unread_changed")
    render json: { unread_count: unread_count }
  end

  def read_all
    notifications.unread.update_all(read_at: Time.current, updated_at: Time.current)
    InAppNotification.broadcast_event!(current_admin_user.id, event: "unread_changed")
    render json: { unread_count: 0 }
  end

  private

  def notifications
    InAppNotification.where(admin_user_id: current_admin_user.id, tenant_id: current_tenant.id)
  end

  def unread_count
    InAppNotification.unread_count_for(current_admin_user)
  end
end
