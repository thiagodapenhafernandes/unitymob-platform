# frozen_string_literal: true

module Field
  class PushSubscriptionsController < BaseController
    skip_before_action :verify_authenticity_token, only: %i[create received native]

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
        delete_duplicate_endpoint_subscriptions!(record)
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
      deactivate_subscription!(record, reason: "destroy_requested") if record
      render json: { ok: true }
    end

    # POST /field/push_subscriptions/native
    # Payload: { platform: "ios"|"android", token: "..." } — vem do plugin
    # @capacitor/push-notifications do app híbrido, não do service worker.
    def native
      platform = params[:platform].to_s
      token = params[:token].to_s

      unless PushSubscription::NATIVE_PLATFORMS.include?(platform)
        return render json: { ok: false, errors: ["platform inválida"] }, status: :unprocessable_entity
      end
      if token.blank?
        return render json: { ok: false, errors: ["token ausente"] }, status: :unprocessable_entity
      end

      delete_old_subscription!(token)

      record = PushSubscription.find_or_initialize_by(admin_user: current_admin_user, endpoint: token)
      record.platform = platform
      record.user_agent = request.user_agent
      record.active = true
      record.last_seen_at = Time.current

      if record.save
        delete_duplicate_endpoint_subscriptions!(record)
        delete_stale_device_subscriptions!(record)
        render json: { ok: true, id: record.id }, status: :created
      else
        render json: { ok: false, errors: record.errors.full_messages }, status: :unprocessable_entity
      end
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
        .find_each { |subscription| deactivate_subscription!(subscription, reason: "old_endpoint_replaced") }
    end

    def delete_duplicate_endpoint_subscriptions!(record)
      PushSubscription
        .where(endpoint: record.endpoint)
        .where.not(id: record.id)
        .find_each { |subscription| deactivate_subscription!(subscription, replacement: record, reason: "same_endpoint_new_login") }
    end

    def delete_stale_device_subscriptions!(record)
      return unless record.persisted?

      scope = PushSubscription.where(admin_user: current_admin_user)
      scope = record.native? ? scope.where(platform: PushSubscription::NATIVE_PLATFORMS) : scope.where(platform: record.platform, user_agent: record.user_agent)

      scope
        .where.not(id: record.id)
        .find_each { |subscription| deactivate_subscription!(subscription, replacement: record, reason: "last_native_login_wins") }
    end

    def deactivate_subscription!(subscription, replacement: nil, reason:)
      return unless subscription&.active?

      subscription.update!(active: false)
      PushDeliveryEvent.record!(
        event_type: replacement ? "subscription_replaced" : "subscription_deduplicated",
        admin_user_id: subscription.admin_user_id,
        push_subscription: subscription,
        endpoint: subscription.endpoint,
        user_agent: subscription.user_agent,
        metadata: {
          reason: reason,
          replacement_subscription_id: replacement&.id,
          replacement_admin_user_id: replacement&.admin_user_id,
          platform: subscription.platform
        }.compact
      )
    end
  end
end
