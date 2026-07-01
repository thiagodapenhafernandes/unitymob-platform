require "rails_helper"

RSpec.describe Admin::UiHelper, type: :helper do
  describe "#ax_badge" do
    it "renderiza a primitive de badge com tom, dot e classe adicional" do
      html = helper.ax_badge("Ativa", tone: :green, dot: true, class_name: "extra-class")

      expect(html).to include("ax-badge")
      expect(html).to include("ax-badge--green")
      expect(html).to include("ax-badge--dot")
      expect(html).to include("extra-class")
      expect(html).to include(">Ativa</span>")
    end
  end
end
