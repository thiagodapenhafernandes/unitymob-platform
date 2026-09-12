require "rails_helper"

RSpec.describe "AI preview controller contract" do
  let(:source) { Rails.root.join("app/javascript/controllers/ai_preview_controller.js").read }

  it "remove o override _method antes de chamar a rota POST da IA" do
    expect(source).to include('body.delete("_method")')
    expect(source).to include('method: button.dataset.aiPreviewMethod || "POST"')
  end
end
