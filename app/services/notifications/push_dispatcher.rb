module Notifications
  # Envia notificações Web Push (VAPID) para um AdminUser.
  # Remove subscriptions expiradas (410 Gone) automaticamente.
  class PushDispatcher
    def self.deliver(admin_user_id:, title:, body:, url: "/field", icon: "/pwa-icon-192", accept_url: nil, tag: nil, urgency: "normal", ttl: 86_400, require_interaction: false)
      new(admin_user_id: admin_user_id).deliver(
        title: title,
        body: body,
        url: url,
        icon: icon,
        accept_url: accept_url,
        tag: tag,
        urgency: urgency,
        ttl: ttl,
        require_interaction: require_interaction
      )
    end

    def initialize(admin_user_id:)
      @admin_user_id = admin_user_id
    end

    # accept_url (opcional): endpoint que o service worker chama em background no
    # clique para registrar o "aceite", abrindo o `url` (ex.: WhatsApp do lead)
    # direto, sem passar por tela do sistema.
    def deliver(title:, body:, url:, icon:, accept_url: nil, tag: nil, urgency: "normal", ttl: 86_400, require_interaction: false)
      unless push_setting.configured?
        Rails.logger.warn("[PushDispatcher] push indisponivel para admin_user_id=#{@admin_user_id}: configuracao incompleta ou desativada")
        record_delivery_event("push_unavailable", tag: tag, urgency: urgency, ttl: ttl)
        return 0
      end

      vapid = vapid_credentials
      subs = PushSubscription.active.where(admin_user_id: @admin_user_id)
      if subs.empty?
        Rails.logger.warn("[PushDispatcher] sem subscriptions ativas para admin_user_id=#{@admin_user_id}")
        record_delivery_event("no_active_subscription", tag: tag, urgency: urgency, ttl: ttl)
        return 0
      end

      payload = {
        title: title,
        body: body,
        url: url,
        icon: icon,
        accept_url: accept_url,
        tag: tag,
        timestamp: Time.current.to_i * 1000,
        require_interaction: require_interaction
      }.compact.to_json
      sent = 0

      subs.find_each do |sub|
        begin
          response = WebPush.payload_send(
            message:       payload,
            endpoint:      sub.endpoint,
            p256dh:        sub.p256dh,
            auth:          sub.auth,
            vapid: {
              subject:     vapid_subject(vapid[:subject]),
              public_key:  vapid[:public_key],
              private_key: vapid[:private_key]
            },
            ttl: ttl,
            urgency: urgency
          )
          sent += 1
          record_delivery_event(
            "provider_accepted",
            subscription: sub,
            tag: tag,
            urgency: urgency,
            ttl: ttl,
            provider_status: response&.code || "ok"
          )
          Rails.logger.info("[PushDispatcher] aceito pelo provedor admin_user_id=#{@admin_user_id} sub=#{sub.id} status=#{response&.code || 'ok'} urgency=#{urgency} ttl=#{ttl}")
        rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
          record_delivery_event(
            "invalid_subscription",
            subscription: sub,
            tag: tag,
            urgency: urgency,
            ttl: ttl
          )
          sub.update_column(:active, false)
        rescue => e
          record_delivery_event(
            "provider_failed",
            subscription: sub,
            tag: tag,
            urgency: urgency,
            ttl: ttl,
            error_class: e.class.name,
            error_message: e.message
          )
          Rails.logger.warn("[PushDispatcher] falha para sub=#{sub.id}: #{e.class} #{e.message}")
        end
      end

      Rails.logger.warn("[PushDispatcher] nenhuma subscription aceitou envio para admin_user_id=#{@admin_user_id}") if sent.zero?
      sent
    end

    private

    def push_setting
      @push_setting ||= PushSetting.instance
    end

    # Credenciais VAPID da conta (PushSetting), com fallback para ENV legado.
    def vapid_credentials
      @vapid_credentials ||= push_setting.vapid_credentials
    rescue ActiveRecord::StatementInvalid
      { subject: ENV["VAPID_SUBJECT_EMAIL"], public_key: ENV["VAPID_PUBLIC_KEY"], private_key: ENV["VAPID_PRIVATE_KEY"] }
    end

    def vapid_configured?
      creds = vapid_credentials
      creds[:public_key].present? && creds[:private_key].present? && creds[:subject].present?
    end

    # Garante o prefixo mailto: exigido pelo protocolo Web Push.
    def vapid_subject(subject)
      subject.to_s.start_with?("mailto:", "http") ? subject : "mailto:#{subject}"
    end

    def record_delivery_event(event_type, subscription: nil, tag: nil, urgency: nil, ttl: nil, **attrs)
      PushDeliveryEvent.record!(
        event_type: event_type,
        admin_user_id: @admin_user_id,
        push_subscription: subscription,
        tag: tag,
        endpoint: subscription&.endpoint,
        user_agent: subscription&.user_agent,
        urgency: urgency,
        ttl: ttl,
        **attrs
      )
    end
  end
end
