require "rails_helper"

RSpec.describe "Navigation loader contract" do
  let(:source) { Rails.root.join("app/javascript/lib/navigation_loader.js").read }

  it "shows from real Turbo lifecycle events instead of sniffing clicks" do
    expect(source).to include('on("turbo:visit"', 'on("turbo:submit-start"')
    expect(source).not_to include('addEventListener("click"')
    expect(source).not_to include("turbo:before-visit")
  end

  it "only hides once the destination is ready" do
    expect(source).to include('on("turbo:load"', "controllersPending()", "framesPending()", "holds.size")
    expect(source).not_to include("SHOW_DELAY_MS")
    expect(source).not_to include("MIN_VISIBLE_MS")
  end

  it "is a single module shared by admin and field layouts, not a per-body controller" do
    expect(Rails.root.join("app/javascript/controllers/admin_navigation_controller.js")).not_to exist
    expect(Rails.root.join("app/javascript/application.js").read).to include('import "lib/navigation_loader"')
    expect(Rails.root.join("config/importmap.rb").read).to include('pin "lib/navigation_loader"')
    %w[admin field].each do |layout|
      expect(Rails.root.join("app/views/layouts/#{layout}.html.erb").read).to include('id="adminNavigationPreloader"')
    end
  end
end
