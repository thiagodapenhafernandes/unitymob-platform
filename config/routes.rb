Rails.application.routes.draw do
  devise_for :admin_users, path: 'admin', controllers: {
    sessions: 'admin/sessions',
    omniauth_callbacks: 'admin/omniauth_callbacks'
  }

  # 2FA: desafio TOTP entre a senha e o sign_in (Admin::SessionsController)
  devise_scope :admin_user do
    get  "admin/two_factor", to: "admin/sessions#two_factor", as: :admin_two_factor
    post "admin/two_factor", to: "admin/sessions#verify_two_factor"
  end

  resources :navigation_events, only: [:create], controller: "public_navigation_events"
  
  # Admin Panel
  get "pwa-icon-:size", to: "pwa_icons#show", as: :pwa_icon, constraints: { size: /192|512/ }

  namespace :admin do
    delete "context_items", to: "context_items#clear", as: :context_items
    delete "context_items/:id", to: "context_items#destroy", as: :context_item, constraints: { id: /[^\/]+/ }

    get 'admin_users/index'
    get 'admin_users/new'
    get 'admin_users/edit'
    get 'admin_users/show'
    resources :profiles
    resources :habitations do
      member do
        post :sync
      end
      collection do
        get :print
        post :export
        get :exports
        get "exports/:export_id", to: "habitations#export_status", as: :export_status
        get "exports/:export_id/download", to: "habitations#download_export", as: :download_export
        delete "exports/:export_id", to: "habitations#destroy_export", as: :destroy_export
        get :filter_inspector
        get :proprietor_options
        get :search_by_code
        post :bulk_publish
        post :bulk_publish_eligibility
      end
    end
    resource :habitation_duplicate, only: [] do
      get :check
    end
    
    resources :attribute_options, only: [:index, :create, :update, :destroy]
    resources :lead_statuses, only: [:index] do
      post :bulk_update, on: :collection
    end
    resources :proprietors do
      collection do
        get :print
        get :export
        post :quick_create
      end
    end

    root to: 'dashboard#index'
    get "dashboard/:section", to: "dashboard#section", as: :dashboard_section

    # Painel do Admin do Sistema (operador da aplicação) — acima da conta.
    get "system", to: "system#index", as: :system
    get "system/users", to: "system#users", as: :system_users
    post "system/users/:admin_user_id/impersonate",
         to: "system#impersonate_user",
         as: :system_user_impersonation
    post "system/tenants/:tenant_id/impersonate_owner",
         to: "system#impersonate_owner",
         as: :system_tenant_owner_impersonation
    # Erros da aplicação (rastreador interno) — visão do Admin do Sistema.
    namespace :system do
      resource :health, only: :show, controller: "health"
      resources :error_events, only: [:index, :show] do
        member do
          patch :resolve
          patch :reopen
        end
      end

      # Notificações Globais: transportes globais (WhatsApp/SMTP/VAPID) usados
      # como fallback opt-in pelas contas + toggles de opt-in por Tenant.
      resource :notification_settings, only: [:edit, :update], controller: "notification_settings" do
        patch :update_tenant_fallbacks
      end
    end

    resource :home_setting, only: [:edit, :update]
    resource :contact_setting, only: [:edit, :update]
    resource :layout_setting, only: [:show, :edit, :update]
    resource :lead_setting, only: [:edit, :update]
    resource :footer_setting, only: [:edit, :update]
    resource :property_setting, only: [:edit, :update] do
      get :review_workflow
    end
    resources :webhook_settings do
      post :test, on: :member
      collection do
        patch :share_tracking
        patch "inbound_tokens/:token_id", to: "webhook_settings#update_inbound_token", as: :inbound_token
        post "inbound_tokens/:token_id/regenerate", to: "webhook_settings#regenerate_inbound_token", as: :regenerate_inbound_token
      end
    end
    resource :whatsapp_integration, only: [:show, :update]
    resource :whatsapp_service_setting, only: [:edit, :update]
    get "manifest", to: "manifests#show", as: :manifest, defaults: { format: :json }
    get "configuracoes-da-conta", to: "account_settings#show", as: :account_settings
    patch "configuracoes-da-conta", to: "account_settings#update"
    resources :presentation_cards, except: [:show]
    resource :email_setting, only: [:edit, :update] do
      post :test
    end
    resource :push_setting, only: [:edit, :update] do
      post :generate_keys
      post :use_env_keys
    end
    resource :ai_integration, only: [:show, :update] do
      post :generate_batch
    end
    resource :google_integration, only: [:show, :update] do
      post :test_calendar
    end
    resource :tracking_integration, only: [:show, :update]
    resource :storage_integration, only: [:show, :update] do
      post :test_connection
      post :publish_public_photos
      post :publish_needed_public_photos
      get :public_photo_publish_status
      post :publish_attachment
      post :publish_habitation_photos
      post :publish_blob
    end
    get :seo_dashboard, to: "seo_dashboard#index"
    get :marketing_opportunities, to: "marketing_opportunities#index"
    get :marketing_properties, to: "marketing_properties#index"
    get :marketing_alerts, to: "marketing_alerts#index"
    get :marketing_tools, to: "marketing_tools#index"
    get :image_migration_status, to: "image_migration_status#index"
    patch "image_migration_status/configuration", to: "image_migration_status#update_configuration", as: :image_migration_configuration
    post "image_migration_status/sync", to: "image_migration_status#sync", as: :sync_image_migration
    post "image_migration_status/retry_failed", to: "image_migration_status#retry_failed", as: :retry_failed_image_migration
    resources :marketing_campaigns, except: :show
    resources :seo_settings, except: :show do
      collection do
        patch :update_strategy
        post :discover
      end
      member do
        post :generate_ai
        patch :toggle
      end
    end
    resources :seo_redirects, only: [:index, :create, :update, :destroy]
    resources :banners
    resources :home_sections do
      member do
        patch :toggle_active
      end
      collection do
        patch :update_order
      end
      resources :home_section_items, only: [:new, :create, :edit, :update, :destroy]
    end
    resources :admin_users, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      post :reset_two_factor, on: :member
      collection do
        get   :hierarchy
        patch :move_hierarchy
        post :sync_from_vista
        get  :vista_sync_status
        post :backfill_brokers
        get  :backfill_brokers_status
      end
    end
    resource :impersonation, only: [:destroy]
    resources :habitations do
      resource :media, only: [:show, :update], controller: "habitation_media" do
        get :modal
        post :upload
        patch :reorder
        patch :visibility
        patch :ambiente
        post :organize
        post :share
        delete :destroy_photo
      end
      post :sync, on: :member
      post :generate_ai_preview, on: :member
      patch :format_ai_suggestion, on: :member
      patch :apply_ai_suggestion, on: :member
      delete "purge_attachment/:association/:attachment_id", on: :member, action: :purge_attachment, as: :purge_attachment
    end
    resources :leads, only: [:index, :show, :update, :destroy] do
      get :attend, on: :member
      post :log_contact, on: :member
      post :reprocess_interest, on: :member
      post :simulate_interest, on: :member
      post :open_whatsapp_conversation, on: :member
      post :activate_whatsapp_template, on: :member
      resources :proposals, only: [:new, :create]
      resources :lead_labels, only: [:index, :create, :update, :destroy] do
        post :toggle, on: :member
      end
      resources :property_interests, only: [:create, :destroy] do
        get :search, on: :collection
      end
    end

    # === Comercial (Tarefas, Agenda, Propostas) ===
    resources :tasks, only: [:index, :create, :update, :destroy] do
      patch :complete, on: :member
    end
    resources :appointments, only: [:index, :create, :update, :destroy]

    # === Automação (workflow builder + regras legadas Quando -> Então) ===
    get "automacoes/new", to: "automation_workflows#new", as: :new_automation_workflow_entry
    resources :automation_events, path: "automacoes/eventos", only: [:index] do
      member do
        post :reprocess
        patch :ignore
      end
    end
    resources :automation_workflows, path: "automacoes/fluxos", only: [:index, :create, :show, :destroy] do
      member do
        get :builder
        patch :save_draft
        patch :publish
        match :simulate, via: [:post, :patch]
      end
    end
    resources :automation_rules, path: "automacoes" do
      patch :toggle_active, on: :member
      post :simulate, on: :member
      collection do
        post :create_example
        post :simulate
        post :test_webhook
      end
    end

    resources :whatsapp_campaigns, path: "whatsapp/disparos" do
      collection do
        get :documentation
        match :preview_audience, via: [:post, :patch]
        match :preview_template, via: [:post, :patch]
        match :send_test, via: [:post, :patch]
      end
      member do
        post :start
        post :pause
        post :resume
        post :cancel
        post :cancel_pending
        post :retry_failed
        get :status
      end
    end
    resources :whatsapp_templates, path: "whatsapp/templates" do
      collection do
        post :sync
        post :upload_media
      end
      member do
        get :new_campaign
      end
    end
    resources :whatsapp_campaign_unsubscribes, path: "whatsapp/descadastros", only: [:index] do
      member do
        patch :reenable
      end
    end
    resources :whatsapp_campaign_recipients, path: "whatsapp/importados", only: [:index]
    resources :whatsapp_sender_numbers, path: "whatsapp/numeros", only: [:create, :update, :destroy] do
      post :test_connection, on: :member
    end
    resources :notification_template_settings, path: "notificacoes/templates", only: [:create, :update, :destroy]

    # === Atendimento WhatsApp (inbox) ===
    resources :whatsapp_conversations, only: [:index, :show], path: "atendimento/whatsapp", controller: "whatsapp_inbox" do
      member do
        post :send_message
        get "messages/:message_id/media", action: :media, as: :message_media
        post "messages/:message_id/react", action: :react
        post "messages/:message_id/toggle_pin", action: :toggle_pin
        post "messages/:message_id/toggle_star", action: :toggle_star
        post "messages/:message_id/forward", action: :forward_message
        post "messages/:message_id/add_to_notes", action: :add_to_notes
        post "messages/:message_id/hide", action: :hide_message
      end
      collection do
        post :sync_templates
      end
    end
    resources :proposals, only: [:edit, :update, :destroy] do
      member do
        patch :send_proposal
        get :pdf
      end
    end

    resources :access_audit_logs, only: [:index]
    resources :data_export_audit_logs, only: [:index]
    resources :presentation_audit_logs, only: [:index]
    resource :access_security, only: [:show, :update], controller: "access_security"
    resource :two_factor_settings, only: [:show, :create, :destroy], controller: "two_factor_settings" do
      post :regenerate_backup_codes
    end
    resources :account_memberships, only: [:index, :create, :destroy]
    resource :account_switch, only: [:create]
    resources :access_control_rules, only: [:create, :update, :destroy]
    resources :trusted_devices, only: [:update, :destroy]
    resources :distribution_rules do
      patch :toggle_active, on: :member
      patch :reorder_agents, on: :member
    end
    resources :meta_integrations, only: [:index] do
      collection do
        post :sync_pages
        post :sync_forms
        delete :disconnect
        get :list_forms
      end
    end
    resource :whatsapp_integration, only: [:show] do
      post :embedded_signup_callback
      delete :disconnect
      patch :phone_settings
      patch :manual_connection
      post :sync_notification_templates
      post :test_connection
      post :send_test
    end
    resource :dwv_integrations, only: [:show, :update] do
      get :status
      post :test_connection
      post :sync_property
      post :sync_now
      post :sync_recent
      post :deactivate_removed
    end
    resource :loft_integrations, only: [:show, :update] do
      get :status
      post :test_connection
      post :sync_property
      post :sync_now
      post :sync_batch
      post :sync_images_now
    end
    resources :portal_integrations, only: [:index, :update], param: :portal do
      post :test_feed, on: :member
      get :preview_feed, on: :member
    end
    resource :scheduling_integration, only: [:show, :update] do
      get "pendentes/:id", action: :pending_property, as: :pending_property
      post :block_day
      delete "block_days/:id", action: :unblock_day, as: :unblock_day
    end
    resources :landing_pages do
      get :preview, on: :collection
    end

    # === Lojas físicas (módulo field) ===
    resources :stores do
      get :geocode, on: :collection
    end

    # === Captação (wizard + dashboard) ===
    resources :captacoes, controller: "habitation_intakes" do
      collection do
        get :dashboard, to: "captacoes#dashboard"
        patch :dashboard_title, to: "captacoes#update_dashboard_title"
        get :export
        get :proprietor_lookup
      end
      member do
        post :publish
        post :submit_for_review
        post :approve
        post :return_to_broker
        post :release_to_site
      end
    end
    resources :captacao_goals

    # === Field settings (toggle da feature flag) ===
    resource :field_settings, only: [:edit, :update] do
      patch :block_agent
      patch :unblock_agent
    end

    # === Field (check-in geolocalizado de corretores) ===
    namespace :field do
      resources :check_ins, only: [:index, :show] do
        post :force_check_out, on: :member
      end
      resources :manual_checkin_requests, only: [:index, :show] do
        member do
          post :approve
          post :reject
        end
      end
      resources :audit_logs, only: [:index, :show]
    end
  end

  # === Rotas do PWA de corretores em campo ===
  # Flag Setting.field_checkin_enabled decide se respondem (retorna 404 com flag off).
  # Usuário ativo pode fazer check-in por padrão; bloqueios pontuais ficam nas configurações de campo.
  namespace :field do
    get "up", to: "health#up"
    get "manifest", to: "manifests#show", as: :manifest, defaults: { format: :json }
    get "", to: "home#show", as: :root
    get "stores/discover", to: "stores#discover"
    resources :check_ins, only: [:new, :create] do
      patch :check_out, on: :member
    end
    resources :location_pings, only: [:create]
    resources :manual_checkin_requests, only: [:new, :create]
    resources :push_subscriptions, only: [:create, :destroy] do
      collection do
        get :vapid_key
        post :received
      end
    end
  end

  namespace :api do
    namespace :v1 do
      namespace :field do
        # (preenchido nas fases 3+)
      end
    end
  end

  # Root
  root 'home#index'
  post "marketing/events", to: "marketing_events#create", as: :marketing_events
  get "sitemap.xml", to: "sitemaps#show", defaults: { format: :xml }, as: :sitemap
  
  # Home pages
  get 'sobre', to: 'home#sobre', as: :sobre
  get 'imobiliaria', to: 'home#sobre' # Alias para "Sobre Nós"
  get 'contato', to: 'home#contato', as: :contato
  
  # Corretores/Brokers
  get 'corretores', to: 'brokers#index', as: :brokers
  
  # Static pages
  get 'trabalhe-conosco', to: 'pages#trabalhe_conosco', as: :trabalhe_conosco
  get 'salute-parcerias', to: 'pages#parcerias', as: :parcerias
  get 'simulador-financiamento', to: 'pages#simulador', as: :simulador
  get 'politica-de-privacidade', to: 'pages#privacy_policy', as: :privacy_policy
  get 'termos-de-uso', to: 'pages#terms_of_use', as: :terms_of_use

  resources :empreendimentos, only: [:index] do
    collection do
      get :search
    end
  end
  get "empreendimentos/:seo_slug",
      to: "empreendimentos#index",
      as: :strategic_empreendimentos,
      constraints: { seo_slug: /balneario-camboriu|praia-brava|centro|barra-sul|frente-mar|vista-mar|lancamentos|prontos-para-morar/ }
  get 'empreendimento/:id', to: 'habitations#show', as: :empreendimento_details
  get 'empreendimetos', to: redirect('/empreendimentos')
  get 'links-uteis', to: 'pages#links_uteis', as: :links_uteis
  get 'corporativos', to: 'pages#corporativos', as: :corporativos
  
  # Autocomplete
  get 'autocomplete/locations', to: 'autocomplete#locations'
  
  # Quick search by code
  get 'buscar-codigo', to: 'habitations#search_by_code', as: :search_by_code
  get 'favoritos', to: 'habitations#favorites', as: :favorite_habitations
  
  # Habitations - SEO friendly routes
  get "imoveis/:seo_slug",
      to: "habitations#index",
      as: :strategic_habitations,
      constraints: { seo_slug: /frente-mar|quadra-mar|lancamentos|prontos-para-morar|centro|barra-sul|praia-brava/ }
  resources :habitations, only: [:index, :show], path: 'imoveis' do
    member do
      post :schedule_visit
      post :share_link
    end
    collection do
      get :autocomplete
      post :search_by_code
    end
  end

  get 'imoveis-com-oportunidade', to: redirect('/imoveis?characteristics[]=opportunity')
  
  # Form submissions
  resources :contacts, only: [:create]
  post 'trabalhe-conosco/submit', to: 'pages#submit_trabalhe_conosco', as: :submit_trabalhe_conosco
  post 'salute-parcerias/submit', to: 'pages#submit_parcerias', as: :submit_parcerias
  # Alternative routes for SEO
  get 'imovel/:id', to: 'habitations#show', as: :property
  get 'venda', to: 'habitations#index', defaults: { transaction_type: 'venda' }, as: :venda
  get 'venda/:category', to: 'habitations#index', defaults: { transaction_type: 'venda' }, as: :venda_category
  get 'aluguel', to: 'habitations#index', defaults: { transaction_type: 'aluguel' }, as: :aluguel
  get 'aluguel/:category', to: 'habitations#index', defaults: { transaction_type: 'aluguel' }, as: :aluguel_category
  
  # API namespace (opcional, para futuras APIs)
  namespace :api do
    namespace :v1 do
      resources :habitations, only: [:index, :show]
      get 'search', to: 'search#index'
      get 'autocomplete', to: 'search#autocomplete'
    end
  end
  
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
  # Health profundo: banco + cache Rails + worker SolidQueue (aponte o uptime monitor aqui).
  get "healthz" => "health#check", as: :health_check
  
  # Public Leads creation
  resources :leads, only: [:create] do
    collection do
      get :whatsapp_url
    end
  end

  # Propostas comerciais — página pública compartilhável
  get "p/:token", to: "proposals#show", as: :public_proposal
  post "p/:token/decidir", to: "proposals#decide", as: :decide_public_proposal

  # Aceite público de convite multi-conta: o token do e-mail é a credencial de
  # entrada; o aceite em si exige login com o e-mail convidado.
  get   "convites/:token", to: "membership_invitations#show",   as: :membership_invitation
  patch "convites/:token", to: "membership_invitations#update"

  # Links seguros de lead (notificação WhatsApp): token é a credencial.
  get "s/:token", to: "secure_links#show", as: :secure_link

  # Galeria pública de fotos selecionadas do imóvel (compartilhamento por WhatsApp).
  get "fotos/:token", to: "habitation_photo_shares#show", as: :habitation_photo_share

  # Mission Control for Jobs — restrito a Admin do Sistema logado.
  # Sem isso, /jobs expõe filas, argumentos de jobs (com PII) e ações
  # de retry/descarte para qualquer visitante.
  authenticate :admin_user, ->(user) { user.system_admin? } do
    mount MissionControl::Jobs::Engine => "/jobs"
  end
  mount ActionCable.server => "/cable"

  # Webhooks
  namespace :webhooks do
    post "inbound/leads", to: "inbound#leads", as: :inbound_leads
    post "meta", to: "meta#receive_leads"
    get "meta", to: "meta#receive_leads"
    get "whatsapp", to: "whatsapp#verify"
    post "whatsapp", to: "whatsapp#receive"
    post "portals/:portal/events", to: "portals#events", as: :portal_events
  end

  namespace :integrations do
    namespace :portals do
      get ":portal/:token", to: "feeds#show", as: :feed_token
      get ":portal/feed", to: "feeds#show", as: :feed
    end
  end

  # A resolução acontece nos controllers. O roteador não deve consultar banco
  # para cada URL desconhecida (especialmente sob tráfego de bots).
  get "/:slug", to: "landing_pages#show", as: :public_landing_page

  # Fallback público final: recupera URLs conhecidas do site antigo e devolve
  # 404 normal para bots/scanners, sem levantar RoutingError no Puma.
  get "/*path", to: "legacy_public_routes#show", constraints: lambda { |req|
    !req.path.start_with?(
      "/admin", "/field", "/api", "/webhooks", "/integrations",
      "/rails", "/assets", "/packs", "/cable", "/jobs"
    )
  }
end
