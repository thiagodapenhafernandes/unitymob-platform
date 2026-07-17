require "rails_helper"

RSpec.describe "tom-select controller contract" do
  let(:source) { Rails.root.join("app/javascript/controllers/tom_select_controller.js").read }

  it "reuses the native Tom Select instance marker to avoid double initialization" do
    expect(source).to include("if (this.element.tomselect)")
    expect(source).to include("this.tomSelect = this.element.tomselect")
    expect(source).to include("new TomSelect(this.element, config)")
  end

  it "only destroys the instance owned by the current element on disconnect" do
    expect(source).to include("this.element.tomselect === this.tomSelect")
    expect(source).to include("this.tomSelect.destroy()")
    expect(source).to include("this.tomSelect = null")
  end
end
