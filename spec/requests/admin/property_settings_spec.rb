require "rails_helper"

RSpec.describe "Admin::PropertySettings", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "allows system admins to configure the property watermark" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get edit_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Config Imóveis")
    expect(response.body).to include("Marca d'água das fotos")
    expect(response.body).to include("Tamanho da marca")
    expect(response.body).to include("Opacidade da marca")
    expect(response.body).to include("Prévia")

    patch admin_property_setting_path, params: {
      property_setting: {
        watermark_position: "bottom_right",
        watermark_size_percentage: 44,
        watermark_opacity_percentage: 65,
        watermark_image: png_upload("watermark.png", "120x60", "none", "white")
      }
    }

    expect(response).to redirect_to(edit_admin_property_setting_path)

    setting = PropertySetting.instance
    expect(setting.watermark_position).to eq("bottom_right")
    expect(setting.watermark_size_percentage).to eq(44)
    expect(setting.watermark_opacity_percentage).to eq(65)
    expect(setting.watermark_image).to be_attached
  end

  it "shows the current watermark image when one is already attached" do
    setting = PropertySetting.instance
    setting.watermark_image.attach(png_upload("marca-atual.png", "120x60", "none", "white"))

    admin = create(:admin_user, :admin)
    sign_in admin

    get edit_admin_property_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Imagem atual")
    expect(response.body).to include("marca-atual.png")
    expect(response.body).to include("Remover imagem atual")
  end

  it "requires fallback admin user when disabling broker capture review layer" do
    admin = create(:admin_user, :admin)
    administrativo = Profile.find_or_initialize_by(name: "Administrativo")
    administrativo.permissions = Profile.default_permissions_for("Administrativo")
    administrativo.save!
    fallback = create(:admin_user, profile: administrativo)
    other_admin = create(:admin_user, :admin, name: "Outro admin")
    intake = create(:habitation, :broker_intake, admin_user: other_admin, intake_status: "draft")
    intake.update_column(:admin_user_id, other_admin.id)

    sign_in admin

    patch admin_property_setting_path, params: {
      property_setting: {
        broker_capture_layer_enabled: "false"
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("deve ser informado")

    patch admin_property_setting_path, params: {
      property_setting: {
        broker_capture_layer_enabled: "false",
        broker_capture_fallback_admin_user_id: fallback.id
      }
    }

    expect(response).to redirect_to(edit_admin_property_setting_path)
    expect(intake.reload.admin_user_id).to eq(fallback.id)
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
end
