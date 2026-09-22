require "rails_helper"

RSpec.describe "Admin::LandingPages formulário", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  it "organiza em página, quais imóveis, Google, textos e publicação, com o resumo ao lado" do
    get new_admin_landing_page_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    titles = html.css(".ax-studio-group .ax-studio-group__head h3").map { |node| node.text.squish }
    expect(titles).to eq(["Página", "Quais imóveis aparecem", "Como o Google vê", "Textos da página", "Publicação"])
    expect(html.at_css("form.ax-studio [data-property-page-preview-target='results']")).to be_present
    expect(html.at_css(".lp-serp [data-seo-snippet-target='url']")).to be_present
    expect(html.at_css("input#activeSwitch")["checked"]).to be_present # página nova já nasce ativa
  end

  it "agrupa as 20 flags sem perder nenhuma (mesmo nome de parâmetro)" do
    get new_admin_landing_page_path

    html = Nokogiri::HTML(response.body)
    expect(html.css(".lp-flags [data-chip-section]").size).to eq(4)
    values = html.css("input[name='landing_page[filter_params][characteristics][]']").map { |input| input["value"] }
    expect(values.size).to eq(20)
    expect(values).to include("frente_mar", "piscina", "opportunity", "exibir_no_site_portal_flag")
  end

  it "ao editar uma página inativa, o interruptor continua desligado e as flags marcadas voltam marcadas" do
    page = admin.tenant.landing_pages.create!(title: "Frente mar", active: false, filter_params: { "characteristics" => ["frente_mar"] })

    get edit_admin_landing_page_path(page)

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("input#activeSwitch")["checked"]).to be_nil
    expect(html.at_css("input#char_frente_mar")["checked"]).to be_present
  end

  it "continua salvando o mesmo contrato de parâmetros" do
    post admin_landing_pages_path, params: { landing_page: { title: "Nova", meta_title: "T", meta_description: "D", active: "1", filter_params: { city: ["Balneário Camboriú"], characteristics: ["piscina"] } } }

    expect(response).to redirect_to(admin_landing_pages_path)
    page = admin.tenant.landing_pages.order(:created_at).last
    expect(page).to have_attributes(title: "Nova", active: true)
    expect(page.filter_params).to include("city" => ["Balneário Camboriú"], "characteristics" => ["piscina"])
  end

  it "prévia conta os imóveis mesmo com os campos vazios dos multiselects" do
    create(:habitation, tenant: admin.tenant, exibir_no_site_flag: true)

    get "/admin/landing_pages/preview", params: { city: [""], neighborhood: [""], development: [""], category: [""], property_codes: [""], q: "", transaction_type: "" }, headers: { "Accept" => "application/json" }

    expect(JSON.parse(response.body)["count"]).to eq(1)
  end

  it "grava só o que foi escolhido: descarta as entradas vazias dos multiselects" do
    post admin_landing_pages_path, params: { landing_page: { title: "Limpa", filter_params: { city: [""], property_codes: ["", "ABC"], characteristics: [""] } } }

    filters = admin.tenant.landing_pages.order(:created_at).last.filter_params
    expect(filters).to include("city" => [], "property_codes" => ["ABC"], "characteristics" => [])
  end

  it "usa a coluna larga para a prévia e o formulário suave" do
    get new_admin_landing_page_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("form.ax-studio.ax-studio--wide")).to be_present
    expect(html.at_css(".ax-studio-form--soft")).to be_present
    expect(html.css(".ax-chip-section").size).to eq(7) # Onde, O quê, Perfil + 4 grupos de flags
  end
end
