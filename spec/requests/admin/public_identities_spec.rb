require "rails_helper"

RSpec.describe "Admin::PublicIdentities", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a aba Configurações com o filtro global" do
    get edit_admin_public_identity_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Configurações")
    expect(response.body).to include("Como exibir o filtro no desktop")
    expect(response.body).to include("Como exibir o filtro no mobile")
  end

  it "salva a foto do painel do filtro global" do
    home_setting = HomeSetting.instance(tenant: admin.tenant)
    photo = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/watermark.png"), "image/png")

    patch admin_public_identity_path, params: {
      home_setting: { filter_panel_background: photo }
    }

    expect(response).to redirect_to(edit_admin_public_identity_path)
    expect(home_setting.reload.filter_panel_background).to be_attached
  end

  describe "foto do menu" do
    let(:home_setting) { HomeSetting.instance(tenant: admin.tenant) }
    let(:photo) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/watermark.png"), "image/png") }

    it "salva, mostra a prévia e remove para voltar à foto do hero" do
      patch admin_public_identity_path, params: { home_setting: { navigation_menu_image: photo } }

      expect(response).to redirect_to(edit_admin_public_identity_path)
      expect(home_setting.reload.navigation_menu_image).to be_attached

      get edit_admin_public_identity_path
      expect(response.body).to include("Foto atual do menu", "Remover e voltar a usar a foto do hero")

      perform_enqueued_jobs do
        patch admin_public_identity_path, params: { home_setting: { remove_navigation_menu_image: "1" } }
      end
      expect(home_setting.reload.navigation_menu_image).not_to be_attached
    end

    it "recusa arquivo que não é imagem web" do
      text = Rack::Test::UploadedFile.new(StringIO.new("oi"), "text/plain", original_filename: "nota.txt")

      patch admin_public_identity_path, params: { home_setting: { navigation_menu_image: text } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("deve ser PNG, JPEG ou WebP de até 8 MB")
      expect(home_setting.reload.navigation_menu_image).not_to be_attached
    end
  end

  it "salva o modo do filtro global junto da identidade" do
    home_setting = HomeSetting.instance(tenant: admin.tenant)

    patch admin_public_identity_path, params: {
      layout_setting: { site_name: "Salute Teste" },
      home_setting: { search_filter_display_mode: "both", mobile_search_filter_display_mode: "floating" }
    }

    expect(response).to redirect_to(edit_admin_public_identity_path)
    expect(home_setting.reload.search_filter_display_mode).to eq("both")
    expect(home_setting.mobile_search_filter_display_mode).to eq("floating")
  end
end
