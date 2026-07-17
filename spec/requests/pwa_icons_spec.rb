require "rails_helper"

RSpec.describe "PWA icons", type: :request do
  before do
    host! "localhost"
    LayoutSetting.instance.update!(
      primary_color: "#10233A",
      secondary_color: "#053C5E",
      accent_color: "#AE8A3C"
    )
  end

  it "gera um PNG maskable com as cores da conta mesmo sem favicon personalizado" do
    get "/pwa-icon-192"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Cache-Control"]).to include("max-age=3600")
    expect(response.body.bytes.first(8)).to eq([137, 80, 78, 71, 13, 10, 26, 10])
  end

  it "mantem os tamanhos oficiais do PWA" do
    get "/pwa-icon-512"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
  end
end
