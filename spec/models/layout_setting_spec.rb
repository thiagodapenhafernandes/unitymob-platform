require "rails_helper"

RSpec.describe LayoutSetting, type: :model do
  describe ".instance" do
    it "preenche os defaults dos fundos estruturais administrativos" do
      setting = described_class.instance

      expect(setting.admin_workspace_color).to eq(LayoutSetting::ADMIN_WORKSPACE_DEFAULT)
      expect(setting.admin_sidebar_color).to eq(LayoutSetting::ADMIN_SIDEBAR_DEFAULT)
    end
  end
end
