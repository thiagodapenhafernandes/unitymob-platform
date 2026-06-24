module Notifications
  # Envia notificações Web Push (VAPID) para um AdminUser.
  # Remove subscriptions expiradas (410 Gone) automaticamente.
  class PushDispatcher
    def self.deliver(admin_user_id:, title:, body:, url: "/field", icon: "/field-icons/icon-192.png")
      new(admin_user_id: admin_user_id).deliver(title: title, body: body, url: url, icon: icon)
    end

    def initialize(admin_user_id:)
      @admin_user_id = admin_user_id
    end

    def deliver(title:, body:, url:, icon:)
      return 0 unless vapid_configured?

      vapid = vapid_credentials
      subs = PushSubscription.active.where(admin_user_id: @admin_user_id)
      return 0 if subs.empty?

      payload = { title: title, body: body, url: url, icon: icon }.to_json
      sent = 0

      subs.find_each do |sub|
        begin
          WebPush.payload_send(
            message:       payload,
            endpoint:      sub.endpoint,
            p256dh:        sub.p256dh,
            auth:          sub.auth,
            vapid: {
              subject:     vapid_subject(vapid[:subject]),
              public_key:  vapid[:public_key],
              private_key: vapid[:private_key]
            },
            ttl: 86_400
          )
          sub.update_column(:last_seen_at, Time.current)
          sent += 1
        rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
          sub.update_column(:active, false)
        rescue => e
          Rails.logger.warn("[PushDispatcher] falha para sub=#{sub.id}: #{e.class} #{e.message}")
        end
      end

      sent
    end

    private

    # Credenciais VAPID da conta (PushSetting), com fallback para ENV legado.
    def vapid_credentials
      @vapid_credentials ||= PushSetting.instance.vapid_credentials
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
  end
end
