require "rails_helper"

RSpec.describe "Admin::LayoutSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "inicia os blocos de configuração recolhidos" do
    get edit_admin_layout_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    panels = html.css(".layout-settings-workspace .ax-panel--collapsible")

    expect(panels.size).to eq(7)
    expect(panels).to all(satisfy do |panel|
      panel.at_xpath('./div[contains(concat(" ", normalize-space(@class), " "), " ax-panel__body ")]')&.key?("hidden")
    end)
    expect(panels).to all(satisfy do |panel|
      panel.at_xpath('./header[contains(concat(" ", normalize-space(@class), " "), " ax-panel__header ")]//button[contains(concat(" ", normalize-space(@class), " "), " ax-panel__trigger ")]')&.[]("aria-expanded") == "false"
    end)
    expect(response.body).to include("Identidade e Marca", "Escopo: conta", "Tema pessoal: Claro")
    expect(response.body).to include("Cada usuário continua escolhendo individualmente")
  end

  it "prioriza os blocos por impacto na identidade e na operação" do
    get edit_admin_layout_setting_path

    expect(response).to have_http_status(:ok)
    expected_priorities = {
      "layout-settings-panel--account-brand" => 1,
      "layout-settings-panel--public-theme" => 2,
      "layout-settings-panel--platform" => 3,
      "layout-settings-panel--admin-theme" => 4,
      "layout-settings-panel--menu-sections" => 5,
      "layout-settings-panel--interest-intelligence" => 6
    }

    expected_priorities.each_key do |class_name|
      expect(response.body).to include(class_name)
    end

    css = Rails.root.join("app/assets/stylesheets/admin_tailwind.css").read
    expected_priorities.each do |class_name, priority|
      expect(css).to include(".#{class_name} { order: #{priority}; }")
    end
  end

  it "entrega os tokens iniciais da previa sem estilos inline" do
    get edit_admin_layout_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    workspace = html.at_css(".layout-settings-workspace[data-controller='layout-theme-preview']")
    contract_swatches = html.css(".layout-settings-token-contract__swatch[data-theme-swatch]")

    expect(workspace).to be_present
    expect(workspace["style"]).to be_nil
    expect(workspace["data-layout-theme-preview-initial-surface"]).to match(/\A#[0-9A-F]{6}\z/i)
    expect(workspace["data-layout-theme-preview-public-primary"]).to match(/\A#[0-9A-F]{6}\z/i)
    expect(contract_swatches.map { |swatch| swatch["data-theme-swatch"] }).to eq(
      %w[surface header workspace sidebar primary ink]
    )
    expect(contract_swatches).to all(satisfy { |swatch| swatch["style"].nil? })
  end

  it "renderiza pares de cor com ids distintos e sincronização Stimulus" do
    get edit_admin_layout_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    controls = html.css('.ax-color-control[data-controller~="ax-color-pair"]')

    expect(controls).not_to be_empty
    expect(controls).to all(satisfy do |control|
      swatch = control.at_css('input[type="color"][data-ax-color-pair-target="swatch"]')
      text = control.at_css('input[type="text"][data-ax-color-pair-target="text"]')
      swatch.present? && text.present? && swatch["id"] != text["id"] && swatch["oninput"].nil? && text["oninput"].nil?
    end)
  end

  describe "PATCH update" do
    it "nega acesso a usuario sem permissao de gerenciar marketing" do
      sign_out admin
      user = create(:admin_user)
      expect(user.can?(:manage, :marketing)).to be(false)
      sign_in user

      get edit_admin_layout_setting_path

      expect(response).to redirect_to(admin_root_path)
      follow_redirect!
      expect(response.body).to include("Você não tem permissão para acessar esta área")
    end

    it "atualiza somente a identidade visual do tenant autenticado" do
      other_tenant = Tenant.create!(name: "Outra marca #{SecureRandom.hex(3)}", slug: "outra-marca-#{SecureRandom.hex(3)}")
      other_setting = LayoutSetting.instance(tenant: other_tenant)
      other_setting.update!(admin_primary_color: "#123456")

      patch admin_layout_setting_path, params: {
        layout_setting: { admin_primary_color: "#654321" }
      }

      expect(response).to redirect_to(edit_admin_layout_setting_path)
      expect(LayoutSetting.instance(tenant: admin.tenant).reload.admin_primary_color).to eq("#654321")
      expect(other_setting.reload.admin_primary_color).to eq("#123456")
    end

    it "permite configurar backgrounds estruturais do workspace administrativo" do
      patch admin_layout_setting_path, params: {
        layout_setting: {
          site_name: "Salute Imóveis",
          admin_area_name: "Plataforma",
          primary_color: "#022B3A",
          secondary_color: "#053C5E",
          accent_color: "#BFAB25",
          admin_surface_color: "#FFFFFF",
          admin_header_color: "#EEF2F7",
          admin_workspace_color: "#F4F6FA",
          admin_sidebar_color: "#FFFFFF",
          admin_primary_color: "#365F8F",
          admin_ink_color: "#1F2733",
          admin_theme_mode: "dark",
          admin_menu_section_colors: {
            product: {
              background_color: "#123456",
              background_opacity: "42",
              text_color: "#234567",
              border_color: "#345678",
              box_shadow: "inset 4px 0 0 #456789"
            }
          }
        }
      }

      expect(response).to redirect_to(edit_admin_layout_setting_path)
      expect(LayoutSetting.instance.reload.admin_workspace_color).to eq("#F4F6FA")
      expect(LayoutSetting.instance.reload.admin_sidebar_color).to eq("#FFFFFF")
      expect(LayoutSetting.instance.reload.admin_theme_mode).to eq("light")
      expect(LayoutSetting.instance.reload.admin_menu_section_styles["product"]).to eq(
        "background_color" => "#123456",
        "background_opacity" => 42,
        "text_color" => "#234567",
        "border_color" => "#345678",
        "box_shadow" => "inset 4px 0 0 #456789"
      )
    end

    it "permite configurar parâmetros objetivos da inteligência de interesse" do
      patch admin_layout_setting_path, params: {
        layout_setting: {
          site_name: "Salute Imóveis",
          admin_area_name: "Plataforma",
          interest_intelligence_enabled: "1",
          interest_intelligence_instructions: InterestIntelligence::SystemInstructions::DEFAULT_TEXT,
          interest_intelligence_settings: {
            minimum_match_score: "72",
            price_tolerance_percent: "18",
            strong_interest_views: "3",
            max_suggestions: "6",
            idle_without_match_hours: "36",
            city_weight: "22",
            neighborhood_weight: "19",
            category_weight: "17",
            bedrooms_weight: "13",
            parking_weight: "7",
            price_weight: "21",
            broker_review_required: "1",
            requires_public_tracking_consent: "1",
            allow_direct_lead_message: "0"
          }
        }
      }

      setting = LayoutSetting.instance.reload
      expect(response).to redirect_to(edit_admin_layout_setting_path)
      expect(setting.interest_intelligence_instructions).to be_blank
      expect(setting.interest_intelligence_settings).to include(
        "minimum_match_score" => 72,
        "price_tolerance_percent" => 18,
        "strong_interest_views" => 3,
        "max_suggestions" => 6,
        "idle_without_match_hours" => 36,
        "city_weight" => 22,
        "neighborhood_weight" => 19,
        "category_weight" => 17,
        "bedrooms_weight" => 13,
        "parking_weight" => 7,
        "price_weight" => 21,
        "broker_review_required" => true,
        "requires_public_tracking_consent" => true,
        "allow_direct_lead_message" => false
      )
    end
  end


  it "usa controles compartilhados e breakpoints na inteligencia de interesse" do
    get edit_admin_layout_setting_path

    html = Nokogiri::HTML(response.body)
    intelligence = html.at_css(".layout-settings-panel--interest-intelligence")
    expect(intelligence).to be_present
    expect(intelligence.css(".ax-control").size).to be >= 12
    expect(intelligence.to_html).not_to include('class="ax-input')

    css = Rails.root.join("app/assets/stylesheets/admin_tailwind.css").read
    expect(css).to include(
      'html[data-admin-theme="dark"] .layout-settings-interest__toggle',
      ".layout-settings-interest__toggle:focus-within",
      ".layout-settings-interest__controls { grid-template-columns: repeat(2, minmax(0, 1fr)); }"
    )
  end
end
