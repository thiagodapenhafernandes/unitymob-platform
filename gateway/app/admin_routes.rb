module Gateway
  module AdminRoutes
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

        def last_event_for(route)
          WebhookEvent.where(webhook_route_id: route.id).order(received_at: :desc).first
        end

        def failed_count_24h(route)
          WebhookEvent.where(webhook_route_id: route.id, status: 'failed').where('received_at > ?', Time.now.utc - 86_400).count
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
        @routes = WebhookRoute.order(:provider, :client_key, :id).to_a
        @unrouted = WebhookEvent.where(status: 'unrouted').order(received_at: :desc).limit(20)
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
    end
  end
end
