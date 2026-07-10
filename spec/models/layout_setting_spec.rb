require "rails_helper"

RSpec.describe LayoutSetting, type: :model do
  describe ".instance" do
    it "preenche os defaults dos fundos estruturais administrativos" do
      setting = described_class.instance

      expect(setting.admin_workspace_color).to eq(LayoutSetting::ADMIN_WORKSPACE_DEFAULT)
      expect(setting.admin_sidebar_color).to eq(LayoutSetting::ADMIN_SIDEBAR_DEFAULT)
    end

    it "preenche os estilos padrão das divisões do menu" do
      styles = described_class.normalized_admin_menu_section_styles({})

      expect(styles.keys).to include("product", "account")
      expect(styles.dig("product", "background_opacity")).to eq(30)
    end

    it "converte a configuração legada de cor única" do
      styles = described_class.normalized_admin_menu_section_styles("product" => "#123456")

      expect(styles["product"]).to include(
        "background_color" => "#123456",
        "text_color" => "#123456",
        "border_color" => "#123456",
        "background_opacity" => 30
      )
    end
  end
end
