require "rails_helper"

RSpec.describe "Marketing events", type: :request do
  before do
    host! "localhost"
  end

  it "ignores passive tracking before LGPD consent" do
    expect {
      post marketing_events_path, params: {
        event_type: "footer_click",
        placement: "footer",
        label: "Contato",
        page_url: "http://localhost/"
      }
    }.not_to change(SeoConversionEvent, :count)

    expect(response).to have_http_status(:accepted)
  end

  it "records passive tracking after LGPD consent" do
    cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"

    expect {
      post marketing_events_path, params: {
        event_type: "footer_click",
        placement: "footer",
        label: "Contato",
        page_url: "http://localhost/"
      }
    }.to change(SeoConversionEvent, :count).by(1)

    expect(response).to have_http_status(:accepted)
  end
end
