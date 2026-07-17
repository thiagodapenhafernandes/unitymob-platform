require "rails_helper"

RSpec.describe "global submit guard" do
  let(:source) { Rails.root.join("app/javascript/submit_guard.js").read }
  let(:application_source) { Rails.root.join("app/javascript/application.js").read }
  let(:importmap_source) { Rails.root.join("config/importmap.rb").read }
  let(:application_css) { Rails.root.join("app/assets/stylesheets/application.scss").read }
  let(:admin_css) { Rails.root.join("app/assets/stylesheets/admin_tailwind.css").read }

  it "is loaded by the shared application bundle used by admin and field layouts" do
    expect(application_source).to include('import "submit_guard"')
    expect(importmap_source).to include('pin "submit_guard"')
  end

  it "blocks duplicate submits by form state instead of disabling the submitter before serialization" do
    expect(source).to include('FORM_GUARD_ATTR = "data-submit-guard-state"')
    expect(source).to include("rejectDuplicateSubmit(event, form)")
    expect(source).to include('event.stopImmediatePropagation()')
    expect(source).not_to include(".disabled = true")
    expect(source).not_to include("setAttribute(\"disabled\"")
  end

  it "supports opt-out and unlocks Turbo validation failures" do
    expect(source).to include('form.dataset.submitGuard === "false"')
    expect(source).to include('form.closest("[data-submit-guard=\'false\']")')
    expect(source).to include('event.detail?.success === false')
    expect(source).to include("event.detail?.fetchResponse?.redirected !== true")
    expect(source).to include("unlockForm(form)")
  end

  it "shows a subtle processing indicator for guarded submit controls" do
    expect(application_css).to include("@keyframes submit-guard-spin")
    expect(application_css).to include("button.is-submitting[type=\"submit\"]::after")
    expect(application_css).to include("input[type=\"submit\"].is-submitting")
    expect(admin_css).to include("@keyframes submit-guard-spin")
    expect(admin_css).to include(".ax-app form.is-submitting button.is-submitting[type=\"submit\"]::after")
  end

  it "does not force modulepreload for non-entrypoint shared imports" do
    expect(importmap_source).to include('pin "public", preload: false')
    expect(importmap_source).to include('pin "ax_toast", preload: false')
    expect(importmap_source).to include('pin "submit_guard", preload: false')
    expect(importmap_source).to include('pin "@rails/actioncable", to: "actioncable.esm.js", preload: false')
  end
end
