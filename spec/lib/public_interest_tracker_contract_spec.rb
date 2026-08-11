require "rails_helper"

RSpec.describe "Public interest tracker contract" do
  let(:source) { Rails.root.join("app/javascript/controllers/public_interest_tracker_controller.js").read }
  let(:public_form_modal) { Rails.root.join("app/views/shared/_public_form_modal.html.erb").read }
  let(:contact_page) { Rails.root.join("app/views/home/contato.html.erb").read }

  it "tracks starts and submissions for all marked public forms" do
    expect(source).to include("publicTrackedForm")
    expect(source).to include("[data-public-interest-form]")
    expect(source).to include(".public-form-modal__form")
    expect(source).to include("lead_form_started")
    expect(source).to include("lead_form_submitted")
    expect(source).to include("publicFormMetadata")
  end

  it "marks reusable public forms and the contact page for public-interest tracking" do
    expect(public_form_modal).to include("public_interest_form: \"public_form\"")
    expect(public_form_modal).to include("public_form_slug: form.slug")
    expect(contact_page).to include("public_interest_form: \"contact\"")
  end
end
