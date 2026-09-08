require "rails_helper"

RSpec.describe "Compartilhamento social do imóvel (OG)", type: :request do
  before { host! "localhost" }

  it "atualiza as prévias após editar o anúncio em qualquer conta sem sobrescrever SEO" do
    other_tenant = Tenant.create!(name: "Outra imobiliária", slug: "social-preview-other")
    hostname = "www.unitymob.com.br"
    TenantDomain.where(hostname: hostname).delete_all
    other_tenant.tenant_domains.create!(hostname: hostname, primary_domain: true)

    [[Tenant.default, "localhost", "Marca A"], [other_tenant, hostname, "Marca B"]].each do |tenant, host, brand|
      host! host
      LayoutSetting.instance(tenant: tenant).update!(site_name: brand)
      habitation = create(:habitation, tenant: tenant, titulo_anuncio: "Apartamento com 1 suíte",
                          descricao_web: "Apartamento com 1 suíte e vista para o mar.",
                          meta_title: "Título SEO preservado", meta_description: "Descrição SEO preservada")
      share = HabitationShareLink.create!(habitation: habitation, admin_user: create(:admin_user, tenant: tenant))
      path = habitation_path(habitation, share_token: share.token, preview: share.updated_at.to_i)

      get path
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('meta[property="og:description"]')["content"]).to include("1 suíte")

      habitation.update!(titulo_anuncio: "Apartamento com 3 dormitórios", dormitorios_qtd: 3,
                         descricao_web: "Apartamento com 3 dormitórios, sendo 1 suíte, e vista para o mar.")

      [path, habitation_path(habitation.reload)].each do |url|
        get url
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        expect(html.at_css('meta[property="og:title"]')["content"]).to eq("#{habitation.codigo} - Apartamento com 3 dormitórios | #{brand}")
        expect(html.at_css('meta[property="og:description"]')["content"]).to eq("Apartamento com 3 dormitórios, sendo 1 suíte, e vista para o mar.")
        expect(html.at_css('meta[name="twitter:description"]')["content"]).to eq(html.at_css('meta[property="og:description"]')["content"])
        expect(html.at_css("title").text).to include("Título SEO preservado")
        expect(html.at_css('meta[name="description"]')["content"]).to eq("Descrição SEO preservada")
      end

      expect(habitation.reload.meta_title).to eq("Título SEO preservado")
      expect(habitation.meta_description.to_plain_text).to eq("Descrição SEO preservada")
    end
  end

  it "usa as características atuais quando o imóvel não tem descrição de anúncio" do
    habitation = create(:habitation, titulo_anuncio: "Apartamento atual", dormitorios_qtd: 3, suites_qtd: 1,
                        descricao_web: nil, descricao_interna: nil, descricao_empreendimento: nil,
                        meta_description: "Descrição antiga com 1 dormitório")

    get habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    description = Nokogiri::HTML(response.body).at_css('meta[property="og:description"]')["content"]
    expect(description).to include("3 dormitorios")
    expect(description).not_to include("Descrição antiga")
  end

  it "usa a foto externa (import Vista/DWV) como og:image e inclui o código no título" do
    code = "8903-#{SecureRandom.hex(3)}"
    habitation = create(:habitation, codigo: code, slug: "apartamento-share-#{SecureRandom.hex(3)}",
                        pictures: [{ "url" => "#{Storage::PublicPropertyPhoto.public_base_url}/spec/foto-8903.jpg", "ordem" => 1, "principal" => true }])

    get habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    og_image = response.body[/<meta property="og:image" content="([^"]*)"/, 1]
    expect(og_image).to include("foto-8903.jpg")
    expect(og_image).not_to include("icon.png")

    og_title = response.body[/<meta property="og:title" content="([^"]*)"/, 1]
    expect(og_title).to include(code)
  end
end
