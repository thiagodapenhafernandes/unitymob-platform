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
      expect(styles["product"]).to include(
        "background_color" => "#E8F0FB",
        "background_opacity" => 100,
        "text_color" => "#245486",
        "border_color" => "#C7D8EE",
        "box_shadow" => "inset 2px 0 0 #365F8F"
      )
      expect(styles["operation"]["box_shadow"]).to eq("inset 2px 0 0 #0F766E")
      expect(styles.dig("account", "background_opacity")).to eq(10)
    end

    it "converte a configuração legada de cor única" do
      styles = described_class.normalized_admin_menu_section_styles("product" => "#123456")

      expect(styles["product"]).to include(
        "background_color" => "#123456",
        "text_color" => "#123456",
        "border_color" => "#123456",
        "background_opacity" => 100,
        "box_shadow" => "inset 2px 0 0 #365F8F"
      )
    end

    it "normaliza o box-shadow e rejeita CSS arbitrário" do
      styles = described_class.normalized_admin_menu_section_styles(
        "product" => { "box_shadow" => "inset 3px 0 0 #123456" },
        "account" => { "box_shadow" => "0 0 10px red; color: red" }
      )

      expect(styles.dig("product", "box_shadow")).to eq("inset 3px 0 0 #123456")
      expect(styles.dig("account", "box_shadow")).to eq("inset 2px 0 0 #365F8F")
    end
  end
end
