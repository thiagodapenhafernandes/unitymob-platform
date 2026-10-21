require "rails_helper"

RSpec.describe "Disponibilidade pública de diária", type: :request do
  let(:tenant) { Tenant.default }
  let(:property) { create(:habitation, tenant: tenant, status: "Diária", exibir_no_site_flag: true, address_attributes: { logradouro: "Rua Um", numero: "1", bairro: "Centro", cidade: "Itajaí", uf: "SC" }) }
  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
  end

  Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
    it "mostra a mesma disponibilidade no tema #{theme}, com navegação e resposta sem cache" do
      tenant.update_columns(public_site_theme: theme)
      property.availability_blocks.create!(tenant: tenant, starts_on: "2026-12-20", ends_on: "2026-12-25")
      get habitation_path(property)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Disponibilidade da locação diária", availability_habitation_path(property))
      detail = Nokogiri::HTML(response.body)
      panel = detail.at_css("aside #rental-availability")
      expect(panel).to be_present
      expect(detail.css("#rental-availability").size).to eq(1)
      expect(detail.css("turbo-frame#availability_habitation_#{property.id}").size).to eq(1)
      aside_html = panel.ancestors("aside").first.to_html
      expect(aside_html.index("public-habitations-show__price-card")).to be < aside_html.index('id="rental-availability"')
      expect(aside_html.index('id="rental-availability"')).to be < aside_html.index('data-action="click-&gt;lead-capture#open"')
      get availability_habitation_path(property, month: "2026-12"), headers: { "Turbo-Frame" => "availability_habitation_#{property.id}" }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
      html = Nokogiri::HTML(response.body)
      expect(html.at_css('time[datetime="2026-12-20"]').parent.text).to include("Indisponível")
      expect(html.at_css('time[datetime="2026-12-26"]').parent.text).to include("Disponível")
      expect(html.at_css('a[rel="next"]')["href"]).to include("2027-01")
      property.availability_blocks.destroy_all
      get availability_habitation_path(property, month: "2026-12")
      expect(response.body).not_to include("__day--blocked")
    end

    it "não exibe agenda para venda ou aluguel mensal no tema #{theme}" do
      tenant.update_columns(public_site_theme: theme)
      ["Venda", "Aluguel"].each do |status|
        property.update!(status: status)
        get habitation_path(property)
        expect(response).to have_http_status(:ok)
        expect(Nokogiri::HTML(response.body).css("#rental-availability")).to be_empty
        expect(response.body).to include("lead-capture#open")
      end
    end
  end

  it "recusa imóvel oculto, não diário e de outra conta" do
    property.update!(exibir_no_site_flag: false)
    get availability_habitation_path(property)
    expect(response).to have_http_status(:not_found)
    property.update!(exibir_no_site_flag: true, status: "Aluguel")
    get availability_habitation_path(property)
    expect(response).to have_http_status(:not_found)
    other = Tenant.create!(name: "Outra pública", slug: "outra-publica-calendar-#{SecureRandom.hex(3)}")
    foreign = create(:habitation, tenant: other, status: "Diária", exibir_no_site_flag: true)
    get availability_habitation_path(foreign)
    expect(response).to have_http_status(:not_found)
  end

  it "trata mês inválido e ano bissexto sem gerar período fora do mês" do
    get availability_habitation_path(property, month: "inválido")
    expect(response).to have_http_status(:ok)
    get availability_habitation_path(property, month: "2028-02")
    expect(response.body).to include('datetime="2028-02-29"')
    expect(response.body).not_to include('datetime="2028-03-01"')
  end
end
