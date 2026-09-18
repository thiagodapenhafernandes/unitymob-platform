require 'uri'

module Gateway
  module AdminRoutes
    PER_PAGE = 25

    def self.registered(app)
      app.set :views, File.join(Gateway.root, 'app/views')
      app.enable :sessions
      app.set :session_secret, ENV.fetch('SESSION_SECRET') { Gateway.env == 'production' ? raise('SESSION_SECRET is required in production') : 'x' * 64 }
      app.set :sessions, httponly: true, secure: Gateway.env == 'production', same_site: :lax

      app.helpers do
        def csrf_token
          session[:csrf_token] ||= SecureRandom.hex(32)
        end

        def verify_csrf!
          halt 403, 'invalid_csrf' unless session[:csrf_token].to_s != '' &&
            Rack::Utils.secure_compare(session[:csrf_token], params[:authenticity_token].to_s)
        end

        def admin_authenticated?
          started = session[:admin_authenticated_at]
          started.is_a?(Integer) && (Time.now.utc.to_i - started) < AdminAuth::SESSION_TTL
        end

        def require_admin!
          redirect '/admin/login' unless admin_authenticated?
        end

        def login_rate_limited?(bucket)
          AdminAuth.rate_limited?("admin-#{bucket}:#{request.ip}", limit: 10, period: 600)
        end

        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def current_page
          [params.fetch('page', 1).to_i, 1].max
        end

        def next_page?(collection)
          collection.size == PER_PAGE
        end

        def last_event_for(route)
          @last_events[route.id]
        end

        def failed_count_24h(route)
          @failed_counts[route.id].to_i
        end

        def incoming_label(route)
          route.provider == 'meta' ? "page_id #{route.page_id}#{" / form_id #{route.form_id}" if route.form_id}" : "phone_number_id #{route.phone_number_id}#{" / waba_id #{route.waba_id}" if route.waba_id.present?}"
        end
      end

      app.before '/admin*' do
        content_type :html
      end

      app.get '/admin' do
        require_admin!
        load_dashboard!
        @route_form = {}
        @mirror_form = mirror_form_defaults
        erb :'admin/dashboard'
      end

      app.get '/admin/routes/:id' do
        require_admin!
        @route = WebhookRoute.find(params.fetch('id'))
        @event_total = admin_events_scope.where(webhook_route_id: @route.id).count
        @events = admin_events_scope.where(webhook_route_id: @route.id).limit(PER_PAGE).offset((current_page - 1) * PER_PAGE).to_a
        erb :'admin/route'
      end

      app.post '/admin/routes' do
        require_admin!
        verify_csrf!
        attrs = admin_route_attributes(params)
        route = WebhookRoute.find_or_initialize_by(admin_route_identity(attrs))
        route.assign_attributes(attrs)
        route.save!
        redirect "/admin/routes/#{route.id}?message=#{Rack::Utils.escape('Rota salva.')}"
      rescue ActiveRecord::RecordInvalid => error
        @route_error = error.record.errors.full_messages.join(', ')
        @route_form = params
        load_dashboard!
        erb :'admin/dashboard'
      rescue ArgumentError => error
        @route_error = error.message
        @route_form = params
        load_dashboard!
        erb :'admin/dashboard'
      end

      app.post '/admin/dev_mirror' do
        require_admin!
        verify_csrf!
        mirror = WebhookMirror.find_or_initialize_by(name: 'Dev Unitymob')
        mirror.assign_attributes(admin_mirror_attributes(params, mirror))
        mirror.save!
        redirect "/admin?message=#{Rack::Utils.escape('Espelho dev salvo.')}"
      rescue ActiveRecord::RecordInvalid => error
        @mirror_error = error.record.errors.full_messages.join(', ')
        @mirror_form = params
        @route_form = {}
        load_dashboard!
        erb :'admin/dashboard'
      rescue ArgumentError => error
        @mirror_error = error.message
        @mirror_form = params
        @route_form = {}
        load_dashboard!
        erb :'admin/dashboard'
      end

      app.get '/admin/login' do
        redirect '/admin' if admin_authenticated?
        erb :'admin/login'
      end

      app.post '/admin/login' do
        verify_csrf!
        if login_rate_limited?('login')
          @error = 'Muitas tentativas. Aguarde alguns minutos.'
          next erb :'admin/login'
        end

        email = params[:email].to_s.strip.downcase
        password = params[:password].to_s
        valid = email == AdminAuth.admin_email &&
          AdminAuth.valid_password?(password, ENV.fetch('GATEWAY_ADMIN_PASSWORD_DIGEST', ''))

        unless valid
          @error = 'Credenciais inválidas.'
          next erb :'admin/login'
        end

        session[:admin_challenge] = AdminAuth.start_challenge
        redirect '/admin/login/verify'
      rescue KeyError, IOError
        @error = 'Não foi possível enviar o código por e-mail. Tente novamente.'
        erb :'admin/login'
      end

      app.get '/admin/login/verify' do
        redirect '/admin/login' unless session[:admin_challenge]
        erb :'admin/verify'
      end

      app.post '/admin/login/verify' do
        verify_csrf!
        redirect '/admin/login' unless session[:admin_challenge]

        if login_rate_limited?('verify')
          @error = 'Muitas tentativas. Aguarde alguns minutos.'
          next erb :'admin/verify'
        end

        if AdminAuth.verify_challenge(session[:admin_challenge], params[:code].to_s)
          session.delete(:admin_challenge)
          session.options[:renew] = true
          session[:admin_authenticated_at] = Time.now.utc.to_i
          redirect '/admin'
        else
          @error = 'Código inválido ou expirado.'
          erb :'admin/verify'
        end
      end

      app.post '/admin/logout' do
        verify_csrf!
        session.clear
        redirect '/admin/login'
      end

      app.helpers do
        def load_dashboard!
          @route_total = admin_routes_scope.count
          @routes = admin_routes_scope.limit(PER_PAGE).offset((current_page - 1) * PER_PAGE).to_a
          route_ids = @routes.map(&:id)
          @last_events = route_ids.empty? ? {} : WebhookEvent.where(webhook_route_id: route_ids).order(received_at: :desc, id: :desc).each_with_object({}) { |event, memo| memo[event.webhook_route_id] ||= event }
          @failed_counts = route_ids.empty? ? {} : WebhookEvent.where(webhook_route_id: route_ids, status: 'failed').where('received_at > ?', Time.now.utc - 86_400).group(:webhook_route_id).count
          @dev_mirror = WebhookMirror.find_by(name: 'Dev Unitymob')
          @mirror_form ||= mirror_form_defaults
        end

        def admin_routes_scope
          latest = WebhookEvent.where.not(webhook_route_id: nil)
            .select('webhook_route_id, MAX(received_at) AS last_received_at')
            .group(:webhook_route_id)
          scope = WebhookRoute
            .joins("LEFT JOIN (#{latest.to_sql}) last_events ON last_events.webhook_route_id = webhook_routes.id")
            .order(Arel.sql('last_events.last_received_at DESC NULLS LAST, webhook_routes.id DESC'))
          scope = scope.where(provider: params['provider']) if %w[whatsapp meta].include?(params['provider'])
          scope = scope.where(active: params['active'] == 'true') if %w[true false].include?(params['active'])
          if params['q'].to_s.strip != ''
            q = "%#{params['q'].to_s.strip}%"
            scope = scope.where('tenant_name ILIKE :q OR client_key ILIKE :q OR target_url ILIKE :q OR phone_number_id ILIKE :q OR waba_id ILIKE :q OR page_id ILIKE :q OR form_id ILIKE :q', q:)
          end
          scope
        end

        def admin_events_scope
          scope = WebhookEvent.includes(:webhook_route).order(received_at: :desc, id: :desc)
          scope = scope.where(provider: params['provider']) if %w[whatsapp meta].include?(params['provider'])
          scope = scope.where(status: params['status']) if WebhookEvent::STATUSES.include?(params['status'])
          scope = scope.where('phone_number_id ILIKE :q OR waba_id ILIKE :q OR page_id ILIKE :q OR form_id ILIKE :q OR external_id ILIKE :q', q: "%#{params['q'].to_s.strip}%") if params['q'].to_s.strip != ''
          scope
        end

        def admin_route_identity(attrs)
          if attrs[:provider] == 'meta'
            { provider: attrs[:provider], page_id: attrs[:page_id], form_id: attrs[:form_id] }
          else
            { provider: attrs[:provider], phone_number_id: attrs[:phone_number_id] }
          end
        end

        def admin_route_attributes(payload)
          provider = payload['route_provider'].to_s
          raise ArgumentError, 'Provider inválido.' unless %w[whatsapp meta].include?(provider)

          target_url = payload['target_url'].to_s.strip
          uri = URI.parse(target_url)
          raise ArgumentError, 'Destino deve ser uma URL http ou https.' unless uri.is_a?(URI::HTTP) && uri.host

          secret = payload['forwarding_secret'].to_s.strip
          secret = SecureRandom.hex(32) if secret.empty?
          attrs = {
            provider:,
            client_key: payload['client_key'].to_s.strip,
            tenant_name: payload['tenant_name'].to_s.strip,
            target_url:,
            forwarding_secret: secret,
            active: payload['active'] != 'false'
          }
          if provider == 'meta'
            attrs[:page_id] = payload['page_id'].to_s.strip
            attrs[:form_id] = payload['form_id'].to_s.strip.presence
          else
            attrs[:phone_number_id] = payload['phone_number_id'].to_s.strip
            attrs[:waba_id] = payload['waba_id'].to_s.strip
          end
          attrs
        rescue URI::InvalidURIError
          raise ArgumentError, 'Destino deve ser uma URL válida.'
        end

        def mirror_form_defaults
          mirror = @dev_mirror || WebhookMirror.find_by(name: 'Dev Unitymob')
          {
            'provider' => mirror&.provider || 'all',
            'target_url' => mirror&.target_url || 'https://dev.unitymob.com.br',
            'active' => mirror&.active? ? 'true' : 'false'
          }
        end

        def admin_mirror_attributes(payload, mirror)
          provider = payload['provider'].to_s
          raise ArgumentError, 'Canal inválido.' unless WebhookMirror::PROVIDERS.include?(provider)

          target_url = payload['target_url'].to_s.strip
          uri = URI.parse(target_url)
          raise ArgumentError, 'Destino deve ser uma URL https.' unless uri.is_a?(URI::HTTPS) && uri.host

          secret = payload['forwarding_secret'].to_s.strip
          secret = mirror.forwarding_secret if secret.empty?
          secret = SecureRandom.hex(32) if secret.to_s.empty?

          {
            provider:,
            target_url:,
            forwarding_secret: secret,
            active: payload['active'] == 'true'
          }
        rescue URI::InvalidURIError
          raise ArgumentError, 'Destino deve ser uma URL válida.'
        end
      end
    end
  end
end
