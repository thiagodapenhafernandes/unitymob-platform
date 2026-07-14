require "rails_helper"

RSpec.describe "Admin::PropertySettings", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }
  before { PropertySetting.instance.update!(broker_capture_layer_enabled: true) }

  it "allows system admins to configure the property watermark" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get edit_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Mídia e marca d'água")
    expect(response.body).to include("property-settings-workspace")
    expect(response.body).to include("ax-workspace-heading", "bi-building-gear")
    expect(response.body).to include("property-settings-preview-panel")
    expect(response.body).to include("property-settings-action-footer")
    expect(response.body).to include("Marca d&#39;água das fotos")
    expect(response.body).to include("Tamanho da marca")
    expect(response.body).to include("Opacidade da marca")
    expect(response.body).to include("Prévia")
    expect(response.body).to include("Busca Inteligente por IA")
    expect(response.body).to include(
      "property-settings-ai-panel--search",
      "property-settings-ai-panel--access",
      "property-settings-ai-panel--aliases",
      "property-settings-ai-panel--sharing"
    )
    expect(response.body).to include("Seleção e validade", "Página pública", "Identificação e lead", "Mensagens operacionais")
    expect(response.body).to include("Recursos da busca", "Interpretação e mensagens", "Consulta e limites", "Profundidade do contexto do catálogo")
    expect(Nokogiri::HTML(response.body).css(".property-settings-ai-search-group").size).to eq(4)
    expect(response.body).to include("Nenhum alias cadastrado", "ax-empty-state")
    html = Nokogiri::HTML(response.body)
    expect(html.css(".ax-range-field").size).to eq(2)
    expect(html.css('.ax-radio-group input[data-watermark-preview-target="positionInput"]').size).to eq(PropertySetting::WATERMARK_POSITIONS.size)
    expect(html.at_css('.ax-file-field input[data-watermark-preview-target="fileInput"]')).to be_present
    expect(html.css(".tab-content, .tab-pane, .property-settings-tabs-card, .property-settings-range, .property-settings-position-option")).to be_empty
    expect(html.css("#property-settings-ai-search .ax-field > label.ax-field-label").size).to be >= 35
    expect(html.at_css('select#development_id[name="development_id"]')).to be_present
    expect(html.at_css('textarea#development_alias_names[name="names"]')).to be_present
    expect(html.css("#property-settings-ai-search label.ax-field")).to be_empty

    setting = PropertySetting.instance
    setting.update!(
      watermark_position: "bottom_right",
      watermark_size_percentage: 44,
      watermark_opacity_percentage: 65,
      watermark_image: png_upload("watermark.png", "120x60", "none", "white")
    )

    expect(setting.watermark_position).to eq("bottom_right")
    expect(setting.watermark_size_percentage).to eq(44)
    expect(setting.watermark_opacity_percentage).to eq(65)
    expect(setting.watermark_image).to be_attached
  end

  it "salva a busca inteligente na nova aba do PropertySetting" do
    setting = PropertySetting.instance
    setting.update!(
      ai_property_search_enabled: true,
      voice_property_search_enabled: true,
      ai_property_search_instructions: "Extraia somente filtros autorizados.",
      ai_property_search_data_source: "database",
      ai_property_search_allowed_fields: %w[transaction_type city price],
      ai_property_search_result_fields: %w[property_code title price],
      ai_property_search_allowed_profiles: %w[account_owner agent],
      ai_property_search_max_results: 12,
      ai_property_search_default_sort: "recent",
      ai_property_search_max_audio_duration_seconds: 45,
      ai_property_search_history_retention_days: 20,
      ai_property_search_fuzzy_similarity_threshold: 0.4,
      ai_property_search_catalog_property_types_limit: 10,
      ai_property_search_catalog_cities_limit: 11,
      ai_property_search_catalog_neighborhoods_limit: 12,
      ai_property_search_catalog_developments_limit: 13,
      ai_property_search_catalog_feature_terms_limit: 14,
      ai_property_search_catalog_alias_names_limit: 4,
      ai_property_search_sharing_enabled: true,
      ai_property_search_share_max_properties: 8,
      ai_property_search_share_expiration_days: 14,
      ai_property_search_visitor_recognition_days: 180,
      ai_property_search_share_title: "Seleção da imobiliária",
      ai_property_search_interest_button_label: "Conversar sobre este imóvel",
      ai_property_search_broker_events_limit: 5
    )

    expect(setting).to have_attributes(
      ai_property_search_enabled: true,
      voice_property_search_enabled: true,
      ai_property_search_max_results: 12,
      ai_property_search_max_audio_duration_seconds: 45,
      ai_property_search_sharing_enabled: true,
      ai_property_search_share_max_properties: 8,
      ai_property_search_share_expiration_days: 14,
      ai_property_search_visitor_recognition_days: 180,
      ai_property_search_share_title: "Seleção da imobiliária",
      ai_property_search_interest_button_label: "Conversar sobre este imóvel",
      ai_property_search_catalog_property_types_limit: 10,
      ai_property_search_catalog_cities_limit: 11,
      ai_property_search_catalog_neighborhoods_limit: 12,
      ai_property_search_catalog_developments_limit: 13,
      ai_property_search_catalog_feature_terms_limit: 14,
      ai_property_search_catalog_alias_names_limit: 4,
      ai_property_search_broker_events_limit: 5
    )
    expect(setting.ai_property_search_allowed_fields).to match_array(%w[transaction_type city price])
    expect(setting.ai_property_search_fuzzy_similarity_threshold).to eq(0.4)
    expect(setting.ai_property_search_catalog_context_limits).to eq(
      property_types: 10,
      cities: 11,
      neighborhoods: 12,
      developments: 13,
      feature_terms: 14,
      alias_names: 4
    )
  end

  it "gerencia aliases de empreendimento na aba da busca inteligente" do
    admin = create(:admin_user, :admin)
    development = create(:habitation, tenant: admin.tenant, tipo: "Empreendimento", nome_empreendimento: "Reserva do Parque", codigo: "RESERVA-#{SecureRandom.hex(3)}")

    DevelopmentAlias.create!(tenant: admin.tenant, development:, name: "Reserva Parque")
    DevelopmentAlias.create!(tenant: admin.tenant, development:, name: "Residencial Reserva")

    expect(DevelopmentAlias.where(tenant: admin.tenant, development:).pluck(:normalized_name)).to contain_exactly("reserva parque", "residencial reserva")
  end

  it "entrega os valores persistidos para a previa sem estilo inline" do
    setting = PropertySetting.instance
    setting.update!(watermark_size_percentage: 41, watermark_opacity_percentage: 73)
    sign_in create(:admin_user, :admin)

    get edit_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    preview_frame = html.at_css(".property-settings-preview-frame[data-watermark-preview-target='frame']")
    expect(preview_frame).to be_present
    expect(preview_frame["style"]).to be_nil
    expect(html.at_css("[data-watermark-preview-target='sizeInput']")["value"]).to eq("41")
    expect(html.at_css("[data-watermark-preview-target='opacityInput']")["value"]).to eq("73")
  end

  it "shows the current watermark image when one is already attached" do
    setting = PropertySetting.instance
    setting.watermark_image.attach(png_upload("marca-atual.png", "120x60", "none", "white"))

    admin = create(:admin_user, :admin)
    sign_in admin

    get edit_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Arquivo atual")
    expect(response.body).to include("marca-atual.png")
    expect(response.body).to include("Remover imagem atual")
  end

  it "explica o fluxo de captação, revisão e publicação em linguagem operacional" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    setting.update!(
      broker_capture_layer_enabled: true,
      required_broker_intake_checks: %w[proprietario endereco fotos],
      returnable_intake_edit_sections: %w[proprietario fotos]
    )

    sign_in admin

    get review_workflow_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Revisão por tipo, categoria e modalidade")
    expect(response.body).to include("ax-workspace-heading", "ax-sticky-action-footer")
    expect(response.body).not_to include("review-workflow-styles", "property_review_workflow")
    expect(response.body).to include("Escolha o cenário que quer configurar")
    expect(response.body).to include("Regra aplicada agora")
    expect(response.body).to include("O sistema vai exigir")
    expect(response.body).to include("Não se aplica neste conjunto")
    expect(response.body).to include("Ajustar regra deste conjunto")
    expect(response.body).to include("Sempre manual")
    expect(response.body).to include("Regra padrão da conta")
  end

  it "deixa claro que revisão desligada não publica automaticamente" do
    admin = create(:admin_user, :admin)
    setting = PropertySetting.instance
    setting.update!(
      broker_capture_layer_enabled: false,
      broker_capture_fallback_admin_user: admin
    )

    sign_in admin

    get review_workflow_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Próximo passo após checklist")
    expect(response.body).to include("Publicar Site")
  end

  it "salva regra específica de revisão para o conjunto selecionado" do
    admin = create(:admin_user, :admin)
    sign_in admin

    with_forgery_protection_disabled do
      patch review_workflow_admin_property_setting_path(
        registration_type: "terrenos",
        category: "Terreno",
        modality: "venda"
      ), params: {
        property_review_policy: {
          broker_capture_layer_enabled: "true",
          required_broker_intake_checks: %w[proprietario area valor_negociacao],
          returnable_intake_edit_sections: %w[proprietario negociacao],
          notify_internal_review_events: "true",
          notify_email_review_events: "false",
          review_notification_emails: ""
        }
      }
    end

    expect(response).to redirect_to(review_workflow_admin_property_setting_path(registration_type: "terrenos", category: "Terreno", modality: "venda"))
    policy = PropertyReviewPolicy.find_by!(tenant: admin.tenant, registration_type: "terrenos", category: "Terreno", modality: "venda")
    expect(policy.active_broker_capture_checks).to eq(%w[proprietario area valor_negociacao])
    expect(policy.active_returnable_intake_edit_sections).to eq(%w[proprietario negociacao])
  end

  it "salva a mesma regra de revisão para múltiplas categorias relacionadas" do
    admin = create(:admin_user, :admin)
    sign_in admin

    with_forgery_protection_disabled do
      patch review_workflow_admin_property_setting_path(
        registration_type: "terrenos",
        category: ["Terreno", "Terreno em Condomínio"],
        modality: "venda"
      ), params: {
        property_review_policy: {
          broker_capture_layer_enabled: "true",
          required_broker_intake_checks: %w[proprietario area],
          returnable_intake_edit_sections: %w[proprietario],
          notify_internal_review_events: "true",
          notify_email_review_events: "false",
          review_notification_emails: ""
        }
      }
    end

    expect(response).to redirect_to(review_workflow_admin_property_setting_path(registration_type: "terrenos", category: ["Terreno", "Terreno em Condomínio"], modality: "venda"))
    policies = PropertyReviewPolicy.where(tenant: admin.tenant, registration_type: "terrenos", modality: "venda").where(category: ["Terreno", "Terreno em Condomínio"])
    expect(policies.size).to eq(2)
    expect(policies.map(&:active_broker_capture_checks)).to all(eq(%w[proprietario area]))
  end

  it "restringe categorias conforme o tipo de cadastro selecionado" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get review_workflow_admin_property_setting_path(
      registration_type: "terrenos",
      category: "Apartamento",
      modality: "venda"
    )

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    category_select = html.at_css('select[name="category[]"][multiple]')
    category_options = category_select.css("option").map { |option| [option["value"], option.text] }
    selected_category = category_select.css("option[selected]").first&.[]("value") ||
                        category_select.css("option").first&.[]("value")

    expect(category_select).to be_present
    expect(category_options.map(&:first)).to include("Terreno", "Terreno em Condomínio")
    expect(category_options.map(&:first)).not_to include("Apartamento")
    expect(selected_category).to eq("Terreno")
    expect(response.body).to include("Terrenos · Terreno · Venda")
  end

  it "requires fallback admin user when disabling broker capture review layer" do
    admin = create(:admin_user, :admin)
    fallback = create(:admin_user, :admin, name: "Fallback admin")
    setting = PropertySetting.instance

    expect(
      setting.update(broker_capture_layer_enabled: false)
    ).to be(false)
    expect(setting.errors[:broker_capture_fallback_admin_user]).to include("deve ser informado quando a revisão administrativa está desativada.")

    intake = create(:habitation, :broker_intake, admin_user: admin, intake_status: "draft", codigo: "INTAKE-#{SecureRandom.hex(3)}")
    intake.update_column(:admin_user_id, admin.id)

    expect(
      setting.update(broker_capture_layer_enabled: false, broker_capture_fallback_admin_user: fallback)
    ).to be(true)
  end

  it "blocks non-admin users" do
    user = create(:admin_user)
    sign_in user

    get edit_admin_property_setting_path

    expect(response).to redirect_to(admin_root_path)
  end

  def png_upload(filename, size, background, fill)
    file = Tempfile.new([File.basename(filename, ".png"), ".png"])
    file.close
    system("magick", "-size", size, "xc:#{background}", "-fill", fill, "-draw", "rectangle 10,10 90,40", file.path, exception: true)
    Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: filename)
  end

  def with_forgery_protection_disabled
    ActionController::Base.allow_forgery_protection = false
    yield
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
