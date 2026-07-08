# frozen_string_literal: true

require "ipaddr"

# Rate limiting com rack-attack — field, login/2FA, criação pública de lead
# e webhooks. Limites generosos: a meta é conter bot/flood, não tráfego real.
#
# Em produção o store é o Rails.cache configurado no ambiente. Em dev/test,
# quando Rails.cache é NullStore, cai num MemoryStore dedicado.

class Rack::Attack
  WHATSAPP_WEBHOOK_PATH = "/webhooks/whatsapp".freeze

  # Cache store: se Rails.cache for NullStore (default em dev/test), usa um
  # MemoryStore dedicado para o rack-attack funcionar.
  Rack::Attack.cache.store =
    if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
      ActiveSupport::Cache::MemoryStore.new
    else
      Rails.cache
    end

  def self.env_ip_list(key)
    ENV.fetch(key, "")
      .split(/[,\s]+/)
      .map(&:strip)
      .reject(&:blank?)
  end

  def self.ip_matches?(request_ip, entries)
    entries.any? do |entry|
      if entry.include?("/")
        IPAddr.new(entry).include?(IPAddr.new(request_ip))
      else
        entry == request_ip
      end
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  def self.public_webhook_path?(req)
    req.path == WHATSAPP_WEBHOOK_PATH
  end

  if Rails.env.development?
    blocklist("development/blocked_ips") do |req|
      blocked_ips = Rack::Attack.env_ip_list("DEV_BLOCKED_IPS")
      blocked_ips.present? && Rack::Attack.ip_matches?(req.ip, blocked_ips)
    end

    blocklist("development/not_allowed_ips") do |req|
      allowed_ips = Rack::Attack.env_ip_list("DEV_ALLOWED_IPS")
      allowed_ips.present? &&
        !Rack::Attack.public_webhook_path?(req) &&
        !Rack::Attack.ip_matches?(req.ip, allowed_ips)
    end
  end

  # --- /field/check_ins (POST) — 5 tentativas por minuto por usuário logado ---
  throttle("field/check_ins/create", limit: 5, period: 60) do |req|
    if req.post? && req.path == "/field/check_ins"
      # warden pode não estar disponível no Rack early chain; tenta a sessão.
      req.env["warden"]&.user(:admin_user)&.id || req.ip
    end
  end

  # --- /field/location_pings (POST) — 2 por segundo, 30 por minuto ---
  throttle("field/location_pings/create", limit: 30, period: 60) do |req|
    if req.post? && req.path == "/field/location_pings"
      req.env["warden"]&.user(:admin_user)&.id || req.ip
    end
  end

  throttle("field/location_pings/burst", limit: 2, period: 1) do |req|
    if req.post? && req.path == "/field/location_pings"
      req.env["warden"]&.user(:admin_user)&.id || req.ip
    end
  end

  # --- /field/manual_checkin_requests (POST) — 3 por hora por usuário ---
  throttle("field/manual_checkin_requests/create", limit: 3, period: 1.hour) do |req|
    if req.post? && req.path == "/field/manual_checkin_requests"
      req.env["warden"]&.user(:admin_user)&.id || req.ip
    end
  end

  # --- Login admin — anti brute force. Devise: POST /admin/sign_in ---
  # Por IP: 10 tentativas / 5 min. Por e-mail: 5 / 20 min (bloqueia ataque
  # distribuído mirando uma conta). Devise não tem lockout nativo aqui.
  throttle("admin/login/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.post? && req.path == "/admin/sign_in"
  end

  throttle("admin/login/email", limit: 5, period: 20.minutes) do |req|
    if req.post? && req.path == "/admin/sign_in"
      email = req.params.dig("admin_user", "email").to_s.downcase.strip.presence
      "#{email}" if email
    end
  end

  # --- Desafio 2FA — 10 códigos / 5 min por IP (além das 5 tentativas por sessão) ---
  throttle("admin/2fa/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.post? && req.path == "/admin/two_factor"
  end

  # --- /webhooks/inbound/* — entrada pública tokenizada por usuário ---
  throttle("webhooks/inbound", limit: 60, period: 1.minute) do |req|
    if req.post? && req.path.start_with?("/webhooks/inbound/")
      authorization = req.get_header("HTTP_AUTHORIZATION").to_s
      bearer_token = authorization[/\ABearer\s+(.+)\z/i, 1].to_s.strip.presence
      token = bearer_token ||
        req.get_header("HTTP_X_WEBHOOK_TOKEN").presence ||
        req.get_header("HTTP_X_INBOUND_WEBHOOK_TOKEN").presence ||
        req.params["token"].presence ||
        "missing"
      "#{req.ip}:#{token}"
    end
  end

  # --- POST /leads público (formulários do site) — 30/min por IP ---
  # Cada create dispara o pipeline caro (distribuição + notificações);
  # 30/min segura bot trivial sem apertar visitantes atrás de NAT.
  # Regex tolera sufixo de formato (/leads.json).
  throttle("public/leads/create", limit: 30, period: 1.minute) do |req|
    req.ip if req.post? && req.path.match?(%r{\A/leads(?:\.[\w-]+)?\z})
  end

  # --- Webhooks Meta (leadgen) e WhatsApp Cloud — 300/min por IP ---
  # Limite LARGO de propósito: a Meta envia rajadas legítimas (campanhas,
  # retries). Serve só para conter flood anônimo no endpoint público.
  throttle("webhooks/meta_whatsapp", limit: 300, period: 1.minute) do |req|
    if req.post? && (req.path == "/webhooks/meta" || req.path == WHATSAPP_WEBHOOK_PATH)
      req.ip
    end
  end

  # Resposta custom para 429.
  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "rate_limited", retry_after: retry_after }.to_json]
    ]
  end
end

# Rack::Attack já é adicionado ao middleware stack pelo seu railtie.
