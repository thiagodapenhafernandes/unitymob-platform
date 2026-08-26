module Notifications
  # Envia notificações Web Push (VAPID) para um AdminUser.
  # Remove subscriptions expiradas (410 Gone) automaticamente.
  class PushDispatcher
    def self.deliver(admin_user_id:, title:, body:, url: "/field", icon: nil, accept_url: nil, tag: nil, urgency: "normal", ttl: 86_400, require_interaction: false, lead_id: nil, metadata: {})
      new(admin_user_id: admin_user_id).deliver(
        title: title,
        body: body,
        url: url,
        icon: icon,
        accept_url: accept_url,
        tag: tag,
        urgency: urgency,
        ttl: ttl,
        require_interaction: require_interaction,
        lead_id: lead_id,
        metadata: metadata
      )
    end

    def initialize(admin_user_id:)
      @admin_user_id = admin_user_id
    end

    # accept_url (opcional): endpoint que o service worker chama em background no
    # clique para registrar o "aceite", abrindo o `url` (ex.: WhatsApp do lead)
    # direto, sem passar por tela do sistema.
    def deliver(title:, body:, url:, icon:, accept_url: nil, tag: nil, urgency: "normal", ttl: 86_400, require_interaction: false, lead_id: nil, metadata: {})
      unless push_setting.enabled?
        Rails.logger.warn("[PushDispatcher] push indisponivel para admin_user_id=#{@admin_user_id}: configuracao incompleta ou desativada")
        record_delivery_event("push_unavailable", tag: tag, urgency: urgency, ttl: ttl, lead_id: lead_id, metadata: metadata)
        return 0
      end

      vapid = vapid_credentials
      subs = PushSubscription.active.where(admin_user_id: @admin_user_id)
      if subs.empty?
        Rails.logger.warn("[PushDispatcher] sem subscriptions ativas para admin_user_id=#{@admin_user_id}")
        record_delivery_event("no_active_subscription", tag: tag, urgency: urgency, ttl: ttl, lead_id: lead_id, metadata: metadata)
        return 0
      end

      payload = {
        title: title,
        body: body,
        url: url,
        icon: icon.presence || tenant_icon_src,
        accept_url: accept_url,
        tag: tag,
        timestamp: Time.current.to_i * 1000,
        require_interaction: require_interaction
      }.compact.to_json
      sent = 0

      subs.find_each do |sub|
        if sub.native?
          deliver_native(sub, title:, body:, url:, tag:, lead_id:, metadata:) && sent += 1
        else
          deliver_web(sub, payload:, vapid:, tag:, urgency:, ttl:, lead_id:, metadata:) && sent += 1
        end
      end

      Rails.logger.warn("[PushDispatcher] nenhuma subscription aceitou envio para admin_user_id=#{@admin_user_id}") if sent.zero?
      sent
    end

    private

    def deliver_web(sub, payload:, vapid:, tag:, urgency:, ttl:, lead_id:, metadata:)
      unless push_setting.configured?
        record_delivery_event("push_unavailable", subscription: sub, tag:, urgency:, ttl:, lead_id:, metadata:)
        return false
      end

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
      record_delivery_event(
        "provider_accepted", subscription: sub, tag:, urgency:, ttl:, lead_id:, metadata:,
        provider_status: response&.code || "ok"
      )
      Rails.logger.info("[PushDispatcher] aceito pelo provedor admin_user_id=#{@admin_user_id} sub=#{sub.id} status=#{response&.code || 'ok'} urgency=#{urgency} ttl=#{ttl}")
      true
    rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
      record_delivery_event("invalid_subscription", subscription: sub, tag:, urgency:, ttl:, lead_id:, metadata:)
      sub.update_column(:active, false)
      false
    rescue => e
      record_delivery_event(
        "provider_failed", subscription: sub, tag:, urgency:, ttl:, lead_id:, metadata:,
        error_class: e.class.name, error_message: e.message
      )
      Rails.logger.warn("[PushDispatcher] falha para sub=#{sub.id}: #{e.class} #{e.message}")
      false
    end

    # Push nativo (iOS/Android via Capacitor) — FCM HTTP v1. Pendente de
    # credenciais reais (FCM_PROJECT_ID / FCM_SERVICE_ACCOUNT_JSON); sem elas,
    # registra "provider_failed" com a mensagem "FCM não configurado" em vez
    # de tentar enviar, para não mascarar o gap como falha de rede.
    def deliver_native(sub, title:, body:, url:, tag:, lead_id:, metadata:)
      result = Notifications::FcmSender.deliver(token: sub.endpoint, title: title, body: body, data: { url: url, tag: tag.to_s })

      if result.success?
        record_delivery_event("provider_accepted", subscription: sub, tag:, lead_id:, metadata:, provider_status: result.status)
        Rails.logger.info("[PushDispatcher] FCM aceito admin_user_id=#{@admin_user_id} sub=#{sub.id} status=#{result.status}")
        return true
      end

      record_delivery_event(
        "provider_failed", subscription: sub, tag:, lead_id:, metadata:,
        error_class: "FcmSender", error_message: result.body.to_s.truncate(500)
      )
      # Token inválido/desinstalado: FCM responde 404 (UNREGISTERED) ou 400.
      sub.update_column(:active, false) if [400, 404].include?(result.status)
      Rails.logger.warn("[PushDispatcher] FCM falhou sub=#{sub.id} status=#{result.status} body=#{result.body}")
      false
    end

    def push_setting
      @push_setting ||= PushSetting.instance
    end

    def admin_user
      @admin_user ||= AdminUser.find_by(id: @admin_user_id)
    end

    def tenant_icon_src
      tenant = admin_user&.tenant
      return "/pwa-icon-192" unless tenant

      Field::PwaIdentity.new(tenant).icon_src(192)
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

    def record_delivery_event(event_type, subscription: nil, tag: nil, urgency: nil, ttl: nil, lead_id: nil, **attrs)
      PushDeliveryEvent.record!(
        event_type: event_type,
        admin_user_id: @admin_user_id,
        push_subscription: subscription,
        tag: tag,
        endpoint: subscription&.endpoint,
        user_agent: subscription&.user_agent,
        urgency: urgency,
        ttl: ttl,
        lead_id: lead_id,
        **attrs
      )
    end
  end
end
