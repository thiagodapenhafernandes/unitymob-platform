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

  it "gera o PNG uma vez por tamanho/versao e serve do cache" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    calls = 0
    allow_any_instance_of(PwaIconsController).to receive(:build_icon_png).and_wrap_original do |m, *args|
      calls += 1
      m.call(*args)
    end

    get "/pwa-icon-192"
    get "/pwa-icon-192"

    expect(response).to have_http_status(:ok)
    expect(calls).to eq(1)
  ensure
    Rails.cache = previous
  end

  it "mantem os tamanhos oficiais do PWA" do
    get "/pwa-icon-512"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
  end
end
