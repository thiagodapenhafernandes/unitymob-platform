Rails.application.routes.draw do
  devise_for :admin_users, path: 'admin', controllers: {
    sessions: 'admin/sessions',
    omniauth_callbacks: 'admin/omniauth_callbacks'
  }
  
  # Admin Panel
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
    
    resource :home_setting, only: [:edit, :update]
    resource :contact_setting, only: [:edit, :update]
    resource :layout_setting, only: [:show, :edit, :update]
    resource :footer_setting, only: [:edit, :update]
    resource :property_setting, only: [:edit, :update] do
      get :review_workflow
    end
    resources :webhook_settings do
      post :test, on: :member
      patch :share_tracking, on: :collection
    end
    resource :whatsapp_integration, only: [:show, :update]
    resource :ai_integration, only: [:show, :update] do
      post :generate_batch
    end
    resource :google_integration, only: [:show, :update]
    resource :tracking_integration, only: [:show, :update]
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
      member do
        post :impersonate
      end
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
        delete :destroy_photo
      end
      post :sync, on: :member
      post :generate_ai_preview, on: :member
      patch :format_ai_suggestion, on: :member
      patch :apply_ai_suggestion, on: :member
      delete "purge_attachment/:association/:attachment_id", on: :member, action: :purge_attachment, as: :purge_attachment
    end
    resources :leads, only: [:index, :show, :update, :destroy] do
      post :log_contact, on: :member
      resources :proposals, only: [:new, :create]
    end

    # === Comercial (Tarefas, Agenda, Propostas) ===
    resources :tasks, only: [:index, :create, :update, :destroy] do
      patch :complete, on: :member
    end
    resources :appointments, only: [:index, :create, :update, :destroy]

    # === Automação (regras Quando -> Então) ===
    resources :automation_rules, path: "automacoes" do
      patch :toggle_active, on: :member
      post :create_example, on: :collection
    end

    # === Atendimento WhatsApp (inbox) ===
    resources :whatsapp_conversations, only: [:index, :show], path: "atendimento/whatsapp", controller: "whatsapp_inbox" do
      member do
        post :send_message
        post :assign_lead
        get :messages
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
    resource :access_security, only: [:show, :update], controller: "access_security"
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
    resources :stores

    # === Captação (wizard + dashboard) ===
    resources :captacoes, controller: "habitation_intakes" do
      collection do
        get :dashboard, to: "captacoes#dashboard"
        patch :dashboard_title, to: "captacoes#update_dashboard_title"
        get :export
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
    resource :field_settings, only: [:edit, :update]

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
  # Corretor precisa estar autenticado via Devise + ter field_agent_enabled=true.
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
      collection { get :vapid_key }
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
  
  # Public Leads creation
  resources :leads, only: [:create] do
    collection do
      get :whatsapp_url
    end
  end

  # Propostas comerciais — página pública compartilhável
  get "p/:token", to: "proposals#show", as: :public_proposal
  post "p/:token/decidir", to: "proposals#decide", as: :decide_public_proposal

  # Mission Control for Jobs
  mount MissionControl::Jobs::Engine => "/jobs"

  # Webhooks
  namespace :webhooks do
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

  # Catch-all route for SEO redirects
  get "/*path", to: "seo_redirects#show", constraints: lambda { |req|
    lookup = "/#{req.params[:path]}"
    query_lookup = req.query_string.present? ? "#{lookup}?#{req.query_string}" : lookup
    SeoRedirect.active.exists?(from_path: query_lookup) || SeoRedirect.active.exists?(from_path: lookup)
  }

  # Catch-all route for public landing pages
  get '/:slug', to: 'landing_pages#show', constraints: lambda { |req|
    LandingPage.exists?(slug: req.params[:slug])
  }, as: :public_landing_page
end
