# frozen_string_literal: true

module Field
  class PushSubscriptionsController < BaseController
    # POST /field/push_subscriptions
    # Payload: { subscription: { endpoint, keys: { p256dh, auth } }, user_agent? }
    def create
      sub_payload = params.require(:subscription).permit(:endpoint, keys: [:p256dh, :auth])
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
      render json: { public_key: ENV["VAPID_PUBLIC_KEY"] }
    end
  end
end
