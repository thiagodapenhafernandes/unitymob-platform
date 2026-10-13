require "rails_helper"

RSpec.describe "Admin::AiIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "mantém busca e voz em quatro blocos visíveis e um salvamento, incluindo campos avançados" do
    get admin_ai_integration_path
    panel = Nokogiri::HTML(response.body).at_css("#ai-integration-voice")
    expect(panel.css("h2").map(&:text)).to eq(["Disponibilidade e acesso", "Como a busca interpreta", "Resultados e mensagens", "Compartilhamento e captação"])
    expect(panel.css(".ax-studio-section[hidden], [role='tab']")).to be_empty
    expect(panel.css("form").size).to eq(1)
    expect(panel.at_css('input[name="ai[section]"]')["value"]).to eq("search")
    expect(panel.css("details").size).to eq(7)
    expect(panel.css("details input[disabled], details textarea[disabled]")).to be_empty
    expect(panel.at_css('textarea[name="property_setting[ai_property_search_instructions]"]')).to be_present
    expect(panel.at_css('[name="property_setting[ai_property_search_price_tolerance_percentage]"]')).to be_present
    expect(panel.at_css('[name="property_setting[ai_property_search_identity_phone_label]"]')).to be_present
    expect(panel.css('[name^="ai[module_bindings]"]')).to be_empty
  end

  it "expõe os três blocos de Leads preservando todos os ajustes e um salvamento" do
    get admin_ai_integration_path
    panel = Nokogiri::HTML(response.body).at_css("#ai-integration-leads")
    expect(panel.css("h2").map(&:text)).to eq(["Ativação e comunicação", "Recomendações de imóveis", "Instruções da IA"])
    expect(panel.css(".ax-studio-section[hidden], [role='tab']")).to be_empty
    expect(panel.css("form").size).to eq(1)
    expect(panel.at_css('input[name="ai[section]"]')["value"]).to eq("interest")
    keys = InterestIntelligence::Settings::NUMBER_FIELDS.map(&:first) + InterestIntelligence::Settings::WEIGHT_FIELDS.keys.map(&:to_s) + InterestIntelligence::Settings::SAFEGUARD_FIELDS.map(&:first)
    keys.each do |key|
      expect(panel.at_css("[id='layout_setting_interest_intelligence_settings_#{key}']")).to be_present
    end
    expect(panel.css("details [disabled]")).to be_empty
    expect(panel.at_css('textarea[name="layout_setting[interest_intelligence_instructions]"]')).to be_present
    expect(panel.css('[name^="ai[module_bindings]"]')).to be_empty
  end

  it "exibe orçamento em reais e salva em centavos pelo formulário atual" do
    Setting.set(Dashboard::AiDiagnosis::MONTHLY_BUDGET_CENTS_SETTING, "1000", tenant: admin.tenant)
    get admin_ai_integration_path
    panel = Nokogiri::HTML(response.body).at_css("#ai-integration-data")
    expect(panel.at_css('[name="ai[dashboard_diagnosis_monthly_budget_reais]"]')["value"]).to eq("10,00")
    expect(panel.css("form").size).to eq(1)
    expect(panel.css('[role="tab"]')).to be_empty
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: { ai: { section: "diagnosis", dashboard_diagnosis_monthly_budget_reais: "25,00", dashboard_diagnosis_enabled: "0" } }
    end
    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-data"))
    expect(Dashboard::AiDiagnosis.monthly_budget_cents(tenant: admin.tenant)).to eq(2500)
    expect(Dashboard::AiDiagnosis.enabled?(tenant: admin.tenant)).to be(false)
  end

  it "rejeita orçamento inválido antes de alterar outras configurações do BI" do
    original_limit = Dashboard::AiDiagnosis.weekly_request_limit(tenant: admin.tenant)
    original_budget = Dashboard::AiDiagnosis.monthly_budget_cents(tenant: admin.tenant)
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: { ai: { section: "diagnosis", dashboard_diagnosis_monthly_budget_reais: "10,001", dashboard_diagnosis_weekly_limit: "9" } }
    end
    expect(flash[:alert]).to include("Informe o teto mensal em reais")
    expect(Dashboard::AiDiagnosis.weekly_request_limit(tenant: admin.tenant)).to eq(original_limit)
    expect(Dashboard::AiDiagnosis.monthly_budget_cents(tenant: admin.tenant)).to eq(original_budget)
  end

  it "mantém IDs únicos e controles de Conexões com o padrão mobile" do
    get admin_ai_integration_path
    html = Nokogiri::HTML(response.body)
    ids = html.css("[id]").map { |node| node["id"] }
    expect(ids).to eq(ids.uniq)
    expect(html.css("#ai-integration-connections .ax-panel--settings").size).to eq(2)
    expect(html.at_css('label #ai_dashboard_diagnosis_enabled')).to be_present
    expect(html.at_css('#ai_dashboard_diagnosis_enabled')["type"]).to eq("checkbox")
    expect(response.body).not_to include("voice ativo", "voice pendente", ">Matching<", ">Voice<")
  end

  it "renderiza remoção do token dedicado sem habilitar o provedor inativo" do
    Ai::Provider.all.each_value do |provider|
      Setting.set(provider.voice_api_key_setting, "dedicated-test-token", tenant: admin.tenant)
    end
    get admin_ai_integration_path
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    active = Ai::Provider.active_key(tenant: admin.tenant)
    Ai::Provider.all.each_key do |key|
      input = html.at_css("#ai_#{key}_clear_voice_api_key")
      expect(input).to be_present
      expect(input.key?("disabled")).to eq(key != active)
    end
  end

  it "renderiza o workspace operacional de IA" do
    get admin_ai_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ai-integration-workspace")
    expect(response.body).to include("Conteúdo")
    expect(response.body).to include("Busca e voz")
    expect(response.body).to include("ai-integration-leads")
    expect(response.body).to include("ai-integration-data")
    expect(response.body).to include("Ativação e comunicação")
    expect(response.body).to include("SEO do site")
    expect(response.body).to include("Salvar ajustes da busca")
    expect(response.body).to include("Provedores de IA")
    expect(response.body).to include("Provedor padrão da conta")
    expect(response.body).to include("Salvar conexões e módulos")
    expect(response.body).to include("Token OpenAI")
    expect(response.body).to include("Token Meta Muse")
    expect(response.body).to include("Modelo de conteúdo")
    expect(response.body).to include("Autenticação")
    expect(response.body).to include("Conta OpenAI")
    expect(response.body).to include("Em breve")
    expect(response.body).to include("Conectar no navegador")
    expect(response.body).to include("Abrir painel da OpenAI")
    expect(response.body).to include("Abrir painel da Meta Muse")
    expect(response.body).to include("Geração em lote")
    expect(response.body).to include("Modelo de interpretação")
    expect(response.body).to include("Modelo de transcrição")
    expect(response.body).to include("Diagnóstico do BI")
    expect(response.body).to include("Parâmetros da resposta")
    expect(response.body).to include("Temperature", "Top P", "Frequency penalty", "Presence penalty")
    expect(response.body).to include("Limite semanal de diagnósticos")
    expect(response.body).to include("Teto mensal estimado")
    expect(response.body).to include("Automático recomendado")
    expect(response.body).to include("Modelo de conteúdo personalizado")
    expect(Nokogiri::HTML(response.body).at_css('#ai-integration-content .ax-progress')).to be_nil
    expect(response.body).to include("Nenhum lote iniciado")
  end

  it "salva conexões de conteúdo e voz no hub sem sobrescrever o prompt" do
    Setting.set(Ai::PropertyContentService::PROMPT_SETTING, "Prompt de conteúdo", "Prompt", tenant: admin.tenant)

    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "provider_connection",
          providers: {
            openai: {
              api_key: "general-token",
              model_choice: Ai::Provider::CUSTOM_VALUE,
              model_custom: "gpt-custom-test",
              voice_api_key: "voice-token",
              voice_model_choice: Ai::Provider::CUSTOM_VALUE,
              voice_model_custom: "gpt-4.1-mini",
              voice_transcription_model_choice: "gpt-4o-mini-transcribe"
            }
          }
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-connections"))
    expect(Setting.get(Ai::PropertyContentService::API_KEY_SETTING, nil, tenant: admin.tenant)).to eq("general-token")
    expect(Setting.get(Ai::PropertyContentService::MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-custom-test")
    expect(Setting.get(Ai::PropertySearch::Configuration::API_KEY_SETTING, nil, tenant: admin.tenant)).to eq("voice-token")
    expect(Setting.get(Ai::PropertySearch::Configuration::MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-4.1-mini")
    expect(Setting.get(Ai::PropertySearch::Configuration::TRANSCRIPTION_MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-4o-mini-transcribe")
    expect(Setting.get(Ai::PropertyContentService::PROMPT_SETTING, nil, tenant: admin.tenant)).to eq("Prompt de conteúdo")
  end

  it "salva prompt e parâmetros de conteúdo sem tocar nas credenciais do hub" do
    Setting.set(Ai::PropertyContentService::MODEL_SETTING, "gpt-keep", "Modelo", tenant: admin.tenant)

    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "content",
          property_enrichment_prompt: "Prompt customizado",
          temperature: "0.2",
          top_p: "0.8",
          frequency_penalty: "0.5",
          presence_penalty: "0.2"
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-content"))
    expect(Setting.get(Ai::PropertyContentService::PROMPT_SETTING, nil, tenant: admin.tenant)).to eq("Prompt customizado")
    expect(Ai::PropertyContentService.response_parameters(tenant: admin.tenant)).to include(
      temperature: 0.2,
      top_p: 0.8,
      frequency_penalty: 0.5,
      presence_penalty: 0.2
    )
    expect(Setting.get(Ai::PropertyContentService::MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-keep")
  end

  it "alterna modelo automático e personalizado pelo hub" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "provider_connection",
          providers: { openai: { model_choice: Ai::Provider::AUTOMATIC_VALUE } }
        }
      }
    end

    expect(Setting.get(Ai::PropertyContentService::MODEL_SETTING, nil, tenant: admin.tenant)).to eq(Ai::Provider::AUTOMATIC_VALUE)
    expect(Ai::PropertyContentService.resolved_model(tenant: admin.tenant)).to eq(OpenAi::ModelCatalog::RESPONSE_FALLBACK_MODEL)
  end

  it "ativa Meta Muse e salva credenciais do provedor" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "provider_connection",
          provider: "muse",
          providers: {
            muse: {
              api_key: "meta-token",
              model_choice: "muse-spark-1.2"
            }
          }
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-connections"))
    expect(Ai::Provider.active_key(tenant: admin.tenant)).to eq("muse")

    expect(Setting.get(Ai::Provider::MUSE_API_KEY_SETTING, nil, tenant: admin.tenant)).to eq("meta-token")
    expect(Setting.get(Ai::Provider::MUSE_MODEL_SETTING, nil, tenant: admin.tenant)).to eq("muse-spark-1.2")
    expect(Ai::PropertyContentService.api_key(tenant: admin.tenant)).to eq("meta-token")
    expect(Ai::PropertyContentService.resolved_model(tenant: admin.tenant)).to eq("muse-spark-1.2")
  end

  it "salva o diagnóstico do BI na aba Dados" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "diagnosis",
          dashboard_diagnosis_enabled: "1",
          dashboard_diagnosis_weekly_limit: "2",
          dashboard_diagnosis_monthly_budget_cents: "2500"
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-data"))
    expect(Setting.get(Dashboard::AiDiagnosis::ENABLED_SETTING, nil, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(Dashboard::AiDiagnosis::WEEKLY_REQUEST_LIMIT_SETTING, nil, tenant: admin.tenant)).to eq("2")
    expect(Setting.get(Dashboard::AiDiagnosis::MONTHLY_BUDGET_CENTS_SETTING, nil, tenant: admin.tenant)).to eq("2500")
  end

  it "salva ajustes da busca inteligente pelo mesmo contrato das configurações de imóveis" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: { section: "search" },
        property_setting: {
          ai_property_search_enabled: "1",
          ai_property_search_language: "pt-BR",
          ai_property_search_max_results: "15",
          ai_property_search_allowed_profiles: %w[agent],
          ai_property_search_temperature: "0.35",
          ai_property_search_price_tolerance_percentage: "12",
          ai_property_search_identity_phone_label: "Seu WhatsApp"
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-voice"))
    setting = PropertySetting.instance
    expect(setting.ai_property_search_enabled).to be(true)
    expect(setting.ai_property_search_language).to eq("pt-BR")
    expect(setting.ai_property_search_max_results).to eq(15)
    expect(setting.ai_property_search_allowed_profiles).to eq(%w[agent])
    expect(setting.ai_property_search_temperature.to_f).to eq(0.35)
    expect(setting.ai_property_search_price_tolerance_percentage).to eq(12)
    expect(setting.ai_property_search_identity_phone_label).to eq("Seu WhatsApp")
  end

  it "salva inteligência de interesse com a mesma normalização do layout" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: { section: "interest" },
        layout_setting: {
          interest_intelligence_enabled: "1",
          interest_intelligence_instructions: "Diretriz da conta",
          interest_intelligence_settings: {
            max_suggestions: "99",
            broker_review_required: "1"
          }
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-leads"))
    layout = LayoutSetting.instance
    expect(layout.interest_intelligence_enabled).to be(true)
    expect(layout.interest_intelligence_instructions).to eq("Diretriz da conta")
    expect(layout.interest_intelligence_settings["max_suggestions"]).to eq(20)
    expect(layout.interest_intelligence_settings["broker_review_required"]).to be(true)
  end

  it "salva estratégia de SEO pelo mesmo escritor do inventário" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: { section: "seo" },
        seo_auto_inventory_enabled: "1",
        seo_auto_apply_enabled: "0",
        seo_ai_auto_generate_enabled: "1",
        seo_discovery_enabled: "0",
        seo_ai_strategy_prompt: "Estratégia da conta"
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-content"))
    expect(Seo::PageTracker.enabled?(tenant: admin.tenant)).to be(true)
    expect(Seo::PageTracker.auto_apply?(tenant: admin.tenant)).to be(false)
    expect(Seo::PageTracker.auto_ai?(tenant: admin.tenant)).to be(true)
    expect(Seo::DiscoveryService.enabled?(tenant: admin.tenant)).to be(false)
    expect(Ai::SeoContentService.instructions(tenant: admin.tenant)).to eq("Estratégia da conta")
  end

  it "expõe o hub de conexão com cascata de autenticação e modelos pré-preenchidos" do
    get admin_ai_integration_path

    html = Nokogiri::HTML(response.body)
    hub = html.at_css('form[action="/admin/ai_integration"] input[name="ai[section]"][value="provider_connection"]')
    expect(hub).to be_present

    %w[openai muse].each do |key|
      token_radio = html.at_css(%(input[name="ai[providers][#{key}][auth_method]"][value="token"]))
      account_radio = html.at_css(%(input[name="ai[providers][#{key}][auth_method]"][value="account"]))
      expect(token_radio).to be_present
      expect(account_radio).to be_present
      expect(token_radio["checked"]).to eq("checked")
    end

    oauth_buttons = html.css('button[disabled]', 'button[aria-disabled="true"]')
    expect(oauth_buttons.map(&:text).join).to include("Conectar no navegador")
    expect(response.body).to include("https://platform.openai.com/api-keys", "https://dev.meta.ai/docs/overview")
    expect(response.body).to include("Modelo de conteúdo", "Modelo de interpretação", "Modelo de transcrição")
    expect(response.body).to include(Ai::PropertyContentService::DEFAULT_MODEL)
  end

  it "usa controles compartilhados e breakpoints na inteligencia de interesse" do
    get admin_ai_integration_path

    html = Nokogiri::HTML(response.body)
    intelligence = html.at_css("#ai-integration-leads")
    expect(intelligence).to be_present
    expect(intelligence.css(".ax-control").size).to be >= 12
    expect(intelligence.to_html).not_to match(/class="ax-input(?![-\w])/)

    css = Rails.root.join("app/assets/stylesheets/admin_tailwind.css").read
    expect(css).to include(
      'html[data-admin-theme="dark"] .layout-settings-interest__toggle',
      ".layout-settings-interest__toggle:focus-within",
      ".layout-settings-interest__controls { grid-template-columns: repeat(2, minmax(0, 1fr)); }"
    )
  end

  it "centraliza vínculos e começa exibindo apenas os campos do provedor selecionado" do
    get admin_ai_integration_path
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('#ai-integration-connections-tab')["aria-selected"]).to eq("true")
    connections = html.at_css('#ai-integration-connections')
    expect(connections.at_css('[data-conditional-reveal-values="openai"][data-conditional-reveal-target="panel"]')["hidden"]).to be_nil
    expect(connections.at_css('[data-conditional-reveal-values="muse"][data-conditional-reveal-target="panel"]')["hidden"]).not_to be_nil
    expect(connections.css('select[name$="[provider]"]').size).to eq(8)
    expect(connections.at_css('input[type="password"][name="ai[providers][openai][api_key]"]')).to be_present
    expect(connections.at_css('input[type="password"][name="ai[providers][muse][voice_api_key]"]')).to be_present
    expect(html.css('#ai-integration-content input[name*="providers"]').size).to eq(0)
  end

  it "salva o vínculo e modelo de cada módulo sem modificar as instruções ou o outro provedor" do
    Setting.set(Ai::Provider::MUSE_MODEL_SETTING, "muse-keep", tenant: admin.tenant)
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: { section: "provider_connection", provider: "openai",
              modules: { seo: { provider: "muse", models: { muse: { choice: "__custom__", custom: "muse-seo" } } },
                         property_search_transcription: { provider: "openai", models: { openai: { choice: "whisper-1" } } } },
              providers: { openai: { api_key: "token" } } }
      }
    end
    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-connections"))
    expect(Ai::ModuleConfiguration.new(:seo, tenant: admin.tenant).model).to eq("muse-seo")
    expect(Ai::ModuleConfiguration.new(:seo, tenant: admin.tenant).provider.key).to eq("muse")
    expect(Ai::ModuleConfiguration.new(:property_search_transcription, tenant: admin.tenant).model).to eq("whisper-1")
    expect(Setting.tenant_get(Ai::Provider::MUSE_MODEL_SETTING, nil, tenant: admin.tenant)).to eq("muse-keep")
  end

  it "não altera padrão nem credenciais se o vínculo for inválido" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: { section: "provider_connection", provider: "muse",
              providers: { muse: { api_key: "new-token" } },
              modules: { seo: { provider: "unknown", models: {} } } }
      }
    end
    expect(flash[:alert]).to include("Provedor de IA inválido")
    expect(Ai::Provider.active_key(tenant: admin.tenant)).to eq("openai")
    expect(Ai::Provider.find("muse").api_key(tenant: admin.tenant)).to eq("")
  end

  it "exige modelo personalizado e preserva vínculos ao salvar outra aba" do
    Ai::ModuleConfiguration.save!({ "seo" => { "provider" => "muse", "model" => "muse-keep" } }, tenant: admin.tenant)
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: { ai: { section: "provider_connection", modules: { seo: { provider: "muse", models: { muse: { choice: "__custom__", custom: "" } } } } } }
    end
    expect(flash[:alert]).to include("Informe o modelo personalizado")
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: { ai: { section: "content", property_enrichment_prompt: "Novo prompt", provider: "muse" } }
    end
    expect(Ai::Provider.active_key(tenant: admin.tenant)).to eq("openai")
    expect(Ai::ModuleConfiguration.new(:seo, tenant: admin.tenant).model).to eq("muse-keep")
  end

  it "bloqueia gravação dos vínculos sem permissão de gerenciar integrações" do
    restricted = create(:admin_user, :field_agent)
    sign_out admin
    sign_in restricted
    with_forgery_protection_disabled do
      patch admin_ai_integration_path(format: :json), params: { ai: { section: "provider_connection", provider: "muse" } }
    end
    expect(response).to have_http_status(:forbidden)
    expect(Ai::Provider.active_key(tenant: restricted.tenant)).to eq("openai")
  end

  it "mantém seleção e campos no mesmo bloco, antes dos ajustes por módulo" do
    get admin_ai_integration_path
    html = Nokogiri::HTML(response.body)
    connections = html.at_css('#ai-integration-connections')
    panels = connections.css('.ax-operational-panel')
    expect(panels.map { |panel| panel['aria-label'] }).to eq(["Provedores de IA", "Uso por módulo"])
    provider_panel = panels.first
    expect(provider_panel.at_css('#ai_provider')).to be_present
    %w[openai muse].each do |key|
      provider = Ai::Provider.find(key)
      expect(provider_panel.at_css("#ai_#{key}_model_choice option[selected]")['value']).to eq(provider.model(tenant: admin.tenant))
      expect(provider_panel.at_css("#ai_#{key}_voice_model_choice option[selected]")['value']).to eq(provider.voice_model(tenant: admin.tenant))
      expect(provider_panel.at_css("#ai_#{key}_voice_transcription_model_choice option[selected]")['value']).to eq(provider.voice_transcription_model(tenant: admin.tenant))
      expect(provider_panel.at_css("#ai_#{key}_api_key")).to be_present
    end
    expect(panels.last.at_css('#ai_module_seo_provider')).to be_present
  end

  it "carrega modelos já salvos do provedor sem substituir por um novo preset" do
    Setting.set(Ai::Provider::MUSE_MODEL_SETTING, "muse-custom-saved", tenant: admin.tenant)
    get admin_ai_integration_path
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('#ai_muse_model_choice option[selected]')['value']).to eq(Ai::Provider::CUSTOM_VALUE)
    expect(html.at_css('#ai_muse_model_custom')['value']).to eq("muse-custom-saved")
  end

  it "mostra herança sem seletores habilitados e expõe exceções já salvas" do
    Ai::ModuleConfiguration.save!({ "seo" => { "provider" => "muse", "model" => "muse-exception" } }, tenant: admin.tenant)
    get admin_ai_integration_path
    html = Nokogiri::HTML(response.body)
    inherited = html.at_css('#ai_module_property_content_exception')
    expect(inherited['checked']).to be_nil
    expect(html.at_css('#ai_module_property_content_provider')['disabled']).not_to be_nil
    expect(html.at_css('#ai_module_seo_exception')['checked']).not_to be_nil
    expect(html.at_css('#ai_module_seo_provider')['disabled']).to be_nil
    expect(response.body).to include("Herdando o preset da conta", "muse-exception")
  end

  it "desativar exceção volta ao preset e ignora os campos manuais enviados" do
    Ai::ModuleConfiguration.save!({ "seo" => { "provider" => "muse", "model" => "muse-exception" } }, tenant: admin.tenant)
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: { ai: { section: "provider_connection",
        modules: { seo: { exception_enabled: "0", provider: "muse", models: { muse: { choice: "__custom__", custom: "muse-exception" } } } } } }
    end
    expect(Ai::ModuleConfiguration.new(:seo, tenant: admin.tenant).binding).to eq("provider" => "", "model" => "")
    expect(Ai::ModuleConfiguration.new(:seo, tenant: admin.tenant).provider.key).to eq("openai")
  end

  it "organiza Conteúdo sem abas internas e mantém formulários e editores independentes" do
    get admin_ai_integration_path
    content = Nokogiri::HTML(response.body).at_css('#ai-integration-content')
    expect(content.css('.ax-operational-panel').map { |panel| panel['aria-label'] }).to eq(["Conteúdo dos imóveis", "SEO do site", "Geração em lote"])
    expect(content.css('[role="tablist"]')).to be_empty
    expect(content.css('.integration-split-layout')).to be_empty
    expect(content.css('input[name="ai[section]"]').map { |input| input['value'] }).to eq(%w[content seo])
    expect(content.at_css('textarea[name="ai[property_enrichment_prompt]"]')['rows']).to eq('8')
    expect(content.at_css('textarea[name="seo_ai_strategy_prompt"]')['rows']).to eq('6')
    expect(content.at_css('details.ax-studio-advanced')['open']).to be_nil
    expect(content.css('details.ax-studio-advanced input[type="number"]').size).to eq(4)
    expect(content.to_html).to include("Salvar conteúdo dos imóveis", "Salvar SEO", "sem revisão manual")
  end

  it "expõe requisito de conexão para lote e preserva progresso de uma execução iniciada" do
    get admin_ai_integration_path
    content = Nokogiri::HTML(response.body).at_css('#ai-integration-content')
    expect(content.at_css('form[action$="generate_batch"] button')['disabled']).not_to be_nil
    expect(content.text).to include("Configure o token do provedor de conteúdo")
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "test-token", tenant: admin.tenant)
    Setting.set("openai_batch_status", "processing", tenant: admin.tenant)
    Setting.set("openai_batch_progress", "35", tenant: admin.tenant)
    get admin_ai_integration_path
    content = Nokogiri::HTML(response.body).at_css('#ai-integration-content')
    expect(content.at_css('form[action$="generate_batch"] button')['disabled']).to be_nil
    expect(content.text).to include("Em processamento")
    progress = content.at_css('.ax-progress progress.ax-progress__bar')
    expect(progress['value'].to_f).to eq(35)
    expect(progress['max']).to eq("100")
    expect(progress['style']).to be_nil
  end

  def with_forgery_protection_disabled
    ActionController::Base.allow_forgery_protection = false
    yield
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
