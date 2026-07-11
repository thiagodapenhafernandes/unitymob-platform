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

  describe "PATCH update" do
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
end
