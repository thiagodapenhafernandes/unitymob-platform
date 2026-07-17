require "rails_helper"

RSpec.describe "Admin habitation form contract" do
  let(:form_source) { Rails.root.join("app/views/admin/habitations/_form.html.erb").read }
  let(:documents_source) { Rails.root.join("app/views/admin/habitations/form_tabs/_documents.html.erb").read }

  it "keeps the primary save action in the property form" do
    expect(form_source).to include('hidden_field_tag :save_navigation, "stay"')
    expect(form_source).to include('name: "save_navigation"')
    expect(form_source).to include('value: "exit"')
  end

  it "accepts images and PDFs for internal document uploads" do
    expect(form_source).to include('accept: "image/*,application/pdf"')
    expect(documents_source.scan('accept: "image/*,application/pdf"').size).to be >= 4
  end
end
