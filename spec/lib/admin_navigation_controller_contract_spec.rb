require "rails_helper"

RSpec.describe "Admin navigation controller contract" do
  let(:controller_source) { Rails.root.join("app/javascript/controllers/admin_navigation_controller.js").read }

  it "does not hide the visible preloader during turbo before-cache" do
    before_cache_handler = controller_source[/handleTurboBeforeCache\(\) \{.*?\n  \}/m]

    expect(controller_source).to include("this.boundBeforeCache = this.handleTurboBeforeCache.bind(this)")
    expect(before_cache_handler).to include("window.queueMicrotask")
    expect(before_cache_handler).not_to include("this.hideNow()")
  end

  it "keeps the preloader bound to real Turbo render events instead of timing guesses" do
    expect(controller_source).to include('document.addEventListener("turbo:before-render", this.boundBeforeRender)')
    expect(controller_source).to include("handleTurboLoad()")
    expect(controller_source).to include("if (this.isTurboPreview()) return")
    expect(controller_source).to include("this.afterNextPaint(() => this.handlePageReady())")
    expect(controller_source).not_to include("SHOW_DELAY_MS")
    expect(controller_source).not_to include("MIN_VISIBLE_MS")
  end
end
