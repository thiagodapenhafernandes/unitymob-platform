# frozen_string_literal: true

module Field
  class PushSubscriptionsController < BaseController
    skip_before_action :verify_authenticity_token, only: %i[create received]

    # POST /field/push_subscriptions
    # Payload: { subscription: { endpoint, expirationTime, keys: { p256dh, auth } }, old_endpoint?, user_agent? }
    def create
      sub_payload = params.require(:subscription).permit(:endpoint, :expirationTime, keys: [:p256dh, :auth])
      delete_old_subscription!(sub_payload[:endpoint])

      record = PushSubscription.find_or_initialize_by(
        admin_user: current_admin_user,
        endpoint:   sub_payload[:endpoint]
      )
      record.p256dh   = sub_payload.dig(:keys, :p256dh)
      record.auth     = sub_payload.dig(:keys, :auth)
      record.platform = "web"
      record.user_agent = request.user_agent
      record.active   = true
      record.last_seen_at = Time.current

      if record.save
        delete_stale_device_subscriptions!(record)
        render json: { ok: true, id: record.id }, status: :created
      else
        render json: { ok: false, errors: record.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /field/push_subscriptions?endpoint=...
    def destroy
      endpoint = params[:endpoint].to_s
      record = PushSubscription.find_by(admin_user: current_admin_user, endpoint: endpoint)
      record&.update(active: false)
      render json: { ok: true }
    end

    # GET /field/push_subscriptions/vapid_key
    def vapid_key
      render json: { public_key: PushSetting.public_key }
    end

    # POST /field/push_subscriptions/received
    # Chamado pelo service worker quando o evento push realmente chegou ao device.
    def received
      endpoint = params[:endpoint].to_s
      record = PushSubscription.find_by(admin_user: current_admin_user, endpoint: endpoint)
      record&.update_columns(last_seen_at: Time.current, updated_at: Time.current)
      PushDeliveryEvent.record!(
        event_type: "device_received",
        admin_user_id: current_admin_user.id,
        push_subscription: record,
        tag: params[:tag].presence,
        endpoint: endpoint,
        user_agent: record&.user_agent || request.user_agent,
        metadata: { reason: params[:reason].presence || "push" }
      )

      Rails.logger.info(
        "[PushSubscription] push recebido no device admin_user_id=#{current_admin_user.id} " \
        "sub=#{record&.id || 'unknown'} reason=#{params[:reason].presence || 'push'} " \
        "tag=#{params[:tag].presence || '-'}"
      )

      render json: { ok: true }
    end

    private

    def delete_old_subscription!(new_endpoint)
      old_endpoint = params[:old_endpoint].to_s
      return if old_endpoint.blank? || old_endpoint == new_endpoint.to_s

      PushSubscription
        .where(admin_user: current_admin_user, endpoint: old_endpoint)
        .update_all(active: false, updated_at: Time.current)
    end

    def delete_stale_device_subscriptions!(record)
      return unless record.persisted?
      return if record.apple_web_push? && params[:old_endpoint].blank?

      PushSubscription
        .where(admin_user: current_admin_user, platform: record.platform, user_agent: record.user_agent)
        .where.not(id: record.id)
        .where.not(endpoint: record.endpoint)
        .update_all(active: false, updated_at: Time.current)
    end
  end
end
