# frozen_string_literal: true

require "ipaddr"

# Rate limiting com rack-attack — field, login/2FA, criação pública de lead
# e webhooks. Limites generosos: a meta é conter bot/flood, não tráfego real.
#
# Em produção o store é o Rails.cache configurado no ambiente. Em dev/test,
# quando Rails.cache é NullStore, cai num MemoryStore dedicado.

class Rack::Attack
  WHATSAPP_WEBHOOK_PATH = "/webhooks/whatsapp".freeze
  PUBLIC_PROPERTY_RATE_LIMIT = ENV.fetch("PUBLIC_PROPERTY_RATE_LIMIT", 120).to_i
  PUBLIC_PROPERTY_LISTING_RATE_LIMIT = ENV.fetch("PUBLIC_PROPERTY_LISTING_RATE_LIMIT", 40).to_i
  PUBLIC_PROPERTY_DEEP_PAGE_RATE_LIMIT = ENV.fetch("PUBLIC_PROPERTY_DEEP_PAGE_RATE_LIMIT", 8).to_i
  PUBLIC_PROPERTY_DEEP_PAGE_THRESHOLD = ENV.fetch("PUBLIC_PROPERTY_DEEP_PAGE_THRESHOLD", 20).to_i

  # Cache store: se Rails.cache for NullStore (default em dev/test), usa um
  # MemoryStore dedicado para o rack-attack funcionar.
  Rack::Attack.cache.store =
    if Rails.env.production? && ENV["REDIS_URL"].present?
      ActiveSupport::Cache::RedisCacheStore.new(
        url: ENV.fetch("RACK_ATTACK_REDIS_URL", ENV.fetch("REDIS_URL")),
        namespace: "unitymob:rate_limit"
      )
    elsif Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
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

  def self.public_property_path?(req)
    return false unless req.get?

    public_property_listing_path?(req) ||
      req.path.match?(%r{\A/imoveis/[^/]+(?:\.[\w-]+)?\z}) ||
      req.path.match?(%r{\A/imovel/[^/]+(?:\.[\w-]+)?\z})
  end

  def self.public_property_listing_path?(req)
    return false unless req.get?

    req.path.match?(%r{\A/(?:imoveis|venda|aluguel|imoveis-com-oportunidade)(?:/[^/]+)?(?:\.[\w-]+)?\z})
  end

  def self.deep_public_property_page?(req)
    return false unless public_property_listing_path?(req)

    page = req.params["page"].to_s
    page.match?(/\A\d+\z/) && page.to_i > PUBLIC_PROPERTY_DEEP_PAGE_THRESHOLD
  end

  def self.html_login_request?(request)
    request.path.in?(["/admin/sign_in", "/admin/two_factor"]) &&
      request.get_header("HTTP_ACCEPT").to_s.include?("text/html")
  end

  def self.login_throttled_page(retry_after)
    minutes = [(retry_after.to_f / 60).ceil, 1].max

    <<~HTML
      <!DOCTYPE html>
      <html lang="pt-BR">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
          <title>Acesso temporariamente limitado</title>
          <style>
            body { min-height: 100vh; margin: 0; display: grid; place-items: center; padding: 24px; box-sizing: border-box; background: #101827; color: #172033; font-family: system-ui, -apple-system, sans-serif; }
            main { width: min(100%, 420px); box-sizing: border-box; padding: 32px; border-radius: 22px; background: #fff; box-shadow: 0 24px 70px rgba(0, 0, 0, .35); text-align: center; }
            h1 { margin: 0 0 12px; font-size: 24px; }
            p { margin: 0 0 22px; color: #5b6575; line-height: 1.55; }
            a { display: inline-flex; padding: 12px 18px; border-radius: 10px; background: #365f8f; color: #fff; font-weight: 700; text-decoration: none; }
          </style>
        </head>
        <body>
          <main>
            <h1>Muitas tentativas de acesso</h1>
            <p>Para proteger sua conta, aguarde cerca de #{minutes} #{minutes == 1 ? "minuto" : "minutos"} antes de tentar novamente.</p>
            <a href="/admin/sign_in">Voltar ao login</a>
          </main>
        </body>
      </html>
    HTML
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

  # --- GET públicos de imóveis — proteção contra crawler/flood de listagem ---
  # Os limites são intencionalmente mais largos para navegação real e mais
  # apertados para paginação profunda, que costuma ser padrão de crawler.
  throttle("public/properties/get/ip", limit: PUBLIC_PROPERTY_RATE_LIMIT, period: 1.minute) do |req|
    req.ip if Rack::Attack.public_property_path?(req)
  end

  throttle("public/properties/listing/ip", limit: PUBLIC_PROPERTY_LISTING_RATE_LIMIT, period: 1.minute) do |req|
    req.ip if Rack::Attack.public_property_listing_path?(req)
  end

  throttle("public/properties/deep_pages/ip", limit: PUBLIC_PROPERTY_DEEP_PAGE_RATE_LIMIT, period: 1.minute) do |req|
    req.ip if Rack::Attack.deep_public_property_page?(req)
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
    Rails.logger.warn(
      "[RackAttack] throttle=#{request.env['rack.attack.matched']} " \
      "ip=#{request.ip} path=#{request.fullpath} " \
      "ua=#{request.user_agent.to_s.truncate(180)}"
    )

    if Rack::Attack.html_login_request?(request)
      [
        429,
        { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => retry_after.to_s },
        [Rack::Attack.login_throttled_page(retry_after)]
      ]
    else
      [
        429,
        { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
        [{ error: "rate_limited", retry_after: retry_after }.to_json]
      ]
    end
  end
end

# Rack::Attack já é adicionado ao middleware stack pelo seu railtie.
