require "rails_helper"

RSpec.describe "Admin::LandingPages construtor de páginas", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  def block_params(type, data = {}, extra = {})
    { block_type: type, position: 0, visible: "1", data: data }.merge(extra)
  end

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  it "abre a página pública na conta do registro no host local" do
    page = tenant.landing_pages.create!(title: "Demonstração", slug: "demo", status: "published")
    host! "dev.unitymob.com.br"
    get admin_landing_pages_path
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("a[title='Ver no site']")["href"]).to eq("http://dev.unitymob.com.br/demo?preview_tenant=#{tenant.slug}")
  end

  describe "tela do editor" do
    it "organiza em Página, Blocos, Google e Salvar, com a prévia ao lado" do
      get new_admin_landing_page_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.css(".ax-guided-step .ax-guided-step__head h2").map { |node| node.text.squish.sub(/\s*opcional\z/, "") })
        .to eq(["Página", "Blocos", "Como o Google vê"])
      expect(html.css(".ax-guided-step.is-collapsible").size).to eq(3)
      expect(html.css(".ax-guided-step.is-open")).to be_empty # tudo recolhido por padrão
      expect(html.at_css("[data-landing-page-builder-target='frame']")).to be_present
      expect(html.at_css(".lp-serp [data-seo-snippet-target='url']")).to be_present
      expect(html.css(".lp-dropdown__item").map { |node| node["data-block-type"] }).to eq(%w[form cover text property_showcase button image video embed section cards indicators testimonials timeline partners team steps gallery callout faq navigation])
      expect(html.css("input[name='landing_page[layout_columns]']").map { |node| node["value"] }).to eq(%w[1 2 3])
      expect(html.at_css("input[name='landing_page[layout_columns]'][checked]")["value"]).to eq("1")
    end

    it "página nova nasce como rascunho sem blocos" do
      get new_admin_landing_page_path

      html = Nokogiri::HTML(response.body)
      expect(html.at_css("input[name='landing_page[status]'][value='draft']")["checked"]).to be_present
      expect(html.css("[data-landing-page-builder-target='list'] [data-block-type]").map { |node| node["data-block-type"] }).to eq([])
      expect(html.css(".lp-template").size).to eq(LandingPages::Templates::ALL.size)
    end

    it "oferece uma demonstração genérica sem vitrine" do
      get new_admin_landing_page_path(template: "demo")
      html = Nokogiri::HTML(response.body)
      types = html.css("[data-landing-page-builder-target='list'] [data-block-type]").map { |node| node["data-block-type"] }
      expect(types).to include("gallery", "section", "text", "indicators", "cards", "button")
      expect(types).not_to include("property_showcase")
      expect(response.body).to include("Página de demonstração")
    end

    it "todos os blocos nascem recolhidos (os moldes dos blocos novos também)" do
      get new_admin_landing_page_path(template: "hybrid")

      html = Nokogiri::HTML(response.body)
      expect(html.css("details.lp-block")).not_to be_empty # cartões e moldes (template) juntos
      expect(html.css("details.lp-block[open]")).to be_empty
    end

    it "o modelo Híbrida monta capa, texto e vitrine; o Em branco não traz bloco" do
      get new_admin_landing_page_path(template: "hybrid")
      types = Nokogiri::HTML(response.body).css("[data-landing-page-builder-target='list'] [data-block-type]").map { |node| node["data-block-type"] }
      expect(types).to eq(%w[cover text property_showcase])

      get new_admin_landing_page_path(template: "blank")
      expect(Nokogiri::HTML(response.body).css("[data-landing-page-builder-target='list'] [data-block-type]")).to be_empty
    end

    it "mantém as 20 flags com nome próprio por bloco e volta marcado o que foi salvo" do
      page = tenant.landing_pages.create!(title: "Frente mar", status: "published")
      page.blocks.create!(block_type: "property_showcase", data: { "filters" => { "characteristics" => ["frente_mar"], "city" => ["Itajaí"] } })

      get edit_admin_landing_page_path(page)

      html = Nokogiri::HTML(response.body)
      inputs = html.css("[data-landing-page-builder-target='list'] input[name='landing_page[blocks_attributes][0][data][filters][characteristics][]']")
      expect(inputs.size).to eq(20)
      expect(inputs.find { |input| input["value"] == "frente_mar" }["checked"]).to be_present
      expect(inputs.find { |input| input["value"] == "piscina" }["checked"]).to be_nil
      expect(html.at_css("select[name='landing_page[blocks_attributes][0][data][filters][city][]'] option[selected]")["value"]).to eq("Itajaí")
    end

    it "mostra o status salvo ao editar uma página inativa" do
      page = tenant.landing_pages.create!(title: "Offline", status: "inactive")

      get edit_admin_landing_page_path(page)

      html = Nokogiri::HTML(response.body)
      expect(html.at_css("input[name='landing_page[status]'][value='inactive']")["checked"]).to be_present
    end
  end

  describe "salvar" do
    it "grava a página com os blocos, normalizando os dados pelo catálogo" do
      post admin_landing_pages_path, params: { landing_page: {
        title: "Institucional", status: "published", meta_title: "T", meta_description: "D",
        blocks_attributes: {
          "0" => block_params("cover", { title: "Olá", overlay: "45", segredo: "x" }, position: 0),
          "1" => block_params("property_showcase", { filters: { city: ["Itajaí"], characteristics: [""], hack: "1" }, per_page: "24" }, position: 1)
        }
      } }

      expect(response).to redirect_to(admin_landing_pages_path)
      page = tenant.landing_pages.order(:created_at).last
      expect(page).to have_attributes(title: "Institucional", status: "published", active: true)
      cover, showcase = page.blocks.ordered.to_a
      expect(cover.data).to include("title" => "Olá", "overlay" => 45)
      expect(cover.data).not_to have_key("segredo")
      expect(showcase.data["per_page"]).to eq(24)
      expect(showcase.data["filters"]).to eq("city" => ["Itajaí"])
    end

    it "'Salvar' continua no editor e 'Salvar e sair' volta à lista" do
      post admin_landing_pages_path, params: { continue: "1", landing_page: { title: "Fica", blocks_attributes: { "0" => block_params("button", { label: "Ir", url: "/contato" }) } } }
      page = tenant.landing_pages.order(:created_at).last
      expect(response).to redirect_to(edit_admin_landing_page_path(page))
    end

    it "grava as colunas da página e a largura de cada bloco; recusa colunas fora de 1 a 3" do
      post admin_landing_pages_path, params: { landing_page: { title: "Colunas", layout_columns: "3", blocks_attributes: { "0" => block_params("text", { heading: "A", span: "1" }), "1" => block_params("video", { url: "https://youtu.be/dQw4w9WgXcQ" }, position: 1) } } }

      page = tenant.landing_pages.find_by!(title: "Colunas")
      expect(page.layout_columns).to eq(3)
      expect(page.blocks.ordered.map { |block| block.data["span"] }).to eq(%w[1 full])

      post admin_landing_pages_path, params: { landing_page: { title: "Colunas demais", layout_columns: "7" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "recusa vídeo fora dos provedores suportados e iframe que não é https" do
      post admin_landing_pages_path, params: { landing_page: { title: "Ruim 2", blocks_attributes: { "0" => block_params("video", { url: "https://example.com/1" }) } } }
      expect(response.body).to include("link válido do YouTube")

      post admin_landing_pages_path, params: { landing_page: { title: "Ruim 3", blocks_attributes: { "0" => block_params("embed", { url: "http://example.com" }) } } }
      expect(response.body).to include("começar com https")
    end

    it "continua aceitando o contrato antigo de filter_params" do
      post admin_landing_pages_path, params: { landing_page: { title: "Antiga", filter_params: { city: ["Balneário Camboriú"], characteristics: ["piscina"] } } }

      expect(response).to redirect_to(admin_landing_pages_path)
      expect(tenant.landing_pages.order(:created_at).last.filter_params).to include("city" => ["Balneário Camboriú"], "characteristics" => ["piscina"])
    end

    it "reordena, oculta e remove blocos já salvos" do
      page = tenant.landing_pages.create!(title: "P", status: "published")
      text = page.blocks.create!(block_type: "text", position: 0, data: { "heading" => "A" })
      button = page.blocks.create!(block_type: "button", position: 1, data: { "label" => "B", "url" => "/b" })
      gone = page.blocks.create!(block_type: "text", position: 2, data: { "heading" => "C" })

      patch admin_landing_page_path(page), params: { landing_page: { blocks_attributes: {
        "0" => block_params("text", { heading: "A" }, id: text.id, position: 1, visible: "0"),
        "1" => block_params("button", { label: "B", url: "/b" }, id: button.id, position: 0),
        "2" => block_params("text", { heading: "C" }, id: gone.id, position: 2, _destroy: "1")
      } } }

      page.reload
      expect(page.blocks.ordered.map(&:id)).to eq([button.id, text.id])
      expect(text.reload.visible).to be(false)
    end

    it "mostra o erro de um bloco inválido e não salva" do
      post admin_landing_pages_path, params: { landing_page: { title: "Ruim", blocks_attributes: { "0" => block_params("button", { label: "", url: "" }) } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("O botão precisa de texto")
      expect(tenant.landing_pages.where(title: "Ruim")).to be_empty
    end
  end


  describe "itens com imagens e seções" do
    it "salva imagem pelo admin, devolve sua chave e mantém o agrupamento após atualização" do
      upload = fixture_file_upload("watermark.png", "image/png")
      post admin_landing_pages_path, params: { landing_page: { title: "Nossa empresa", blocks_attributes: {
        "0" => block_params("section", { heading: "Equipe", columns: "3" }),
        "1" => block_params("team", { column: "2", items: { "100" => { row_key: "100", title: "Maria", label: "Corretora" } } }, position: 1, item_uploads: { "100" => upload })
      } } }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:created)
      page = tenant.landing_pages.find_by!(title: "Nossa empresa")
      team = page.blocks.last
      key = team.value(:items).first["image_key"]
      expect(key).to be_present
      expect(team.item_image(team.value(:items).first).blob.metadata).to include("landing_page_item_key" => key)
      expect(JSON.parse(response.body)["blocks"].last["item_image_keys"]).to eq([key])

      patch admin_landing_page_path(page), params: { landing_page: { blocks_attributes: {
        "1" => { id: team.id, data: team.data.merge("column" => "3") }
      } } }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(team.reload.value(:column)).to eq("3")
      expect(team.item_images.count).to eq(1)
      get edit_admin_landing_page_path(page)
      expect(response.body).to include(key)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css("details[data-block-type='team'] input[name$='[id]']")["value"]).to eq(team.id.to_s)

      patch admin_landing_page_path(page), params: { landing_page: { blocks_attributes: {
        "2" => block_params("team", team.data, position: 2, copy_images_from: team.id)
      } } }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      copied = page.blocks.reload.last
      expect(copied.item_image(copied.value(:items).first).blob_id).to eq(team.item_image(team.value(:items).first).blob_id)
    end

    it "não permite recuperar imagens usando uma chave de outra conta" do
      upload = fixture_file_upload("watermark.png", "image/png")
      other = Tenant.create!(name: "Outra conta", slug: "outra-#{SecureRandom.hex(3)}")
      foreign_page = other.landing_pages.create!(title: "Outra conta")
      foreign = foreign_page.blocks.create!(block_type: "team", position: 0, data: { items: [{ row_key: "0", title: "Outra pessoa" }] }, item_uploads: { "0" => upload })
      key = foreign.value(:items).first["image_key"]
      mine = tenant.landing_pages.create!(title: "Minha conta").blocks.create!(block_type: "team", position: 0, data: { items: [{ title: "Minha pessoa", image_key: key }] })
      expect(mine.item_image(mine.value(:items).first)).to be_nil
    end
  end

  describe "autosave (JSON)" do
    let(:json) { { "Accept" => "application/json" } }

    it "cria sempre como rascunho, mesmo se vier outro status, e devolve os ids dos blocos por posição" do
      post admin_landing_pages_path, params: { landing_page: { title: "Auto", status: "published", blocks_attributes: { "0" => block_params("text", { heading: "A" }, position: 0) } } }, headers: json

      expect(response).to have_http_status(:created)
      page = tenant.landing_pages.find_by!(title: "Auto")
      expect(page.status).to eq("draft")
      body = JSON.parse(response.body)
      expect(body).to include("ok" => true, "update_url" => admin_landing_page_path(page), "slug" => page.slug)
      expect(body["blocks"]).to eq([{ "position" => 0, "id" => page.blocks.first.id, "item_image_keys" => [] }])
    end

    it "atualiza rascunho sem mudar o status e sem duplicar blocos já salvos" do
      page = tenant.landing_pages.create!(title: "Rasc", status: "draft")
      text = page.blocks.create!(block_type: "text", position: 0, data: { "heading" => "A" })

      patch admin_landing_page_path(page), params: { landing_page: { title: "Rasc 2", status: "published", blocks_attributes: { "0" => block_params("text", { heading: "B" }, id: text.id) } } }, headers: json

      expect(response).to have_http_status(:ok)
      expect(page.reload).to have_attributes(title: "Rasc 2", status: "draft")
      expect(page.blocks.pluck(:id)).to eq([text.id])
      expect(text.reload.data["heading"]).to eq("B")
    end

    it "não salva sozinha uma página publicada" do
      page = tenant.landing_pages.create!(title: "No ar", status: "published")

      patch admin_landing_page_path(page), params: { landing_page: { title: "Mudou" } }, headers: json

      expect(response).to have_http_status(:conflict)
      expect(page.reload.title).to eq("No ar")
    end

    it "devolve o erro do bloco inválido" do
      post admin_landing_pages_path, params: { landing_page: { title: "Ruim", blocks_attributes: { "0" => block_params("button", { label: "", url: "" }) } } }, headers: json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"].join).to include("O botão precisa de texto")
    end
  end

  describe "prévia" do
    it "renderiza a página real com blocos ainda não salvos, na ordem da tela, sem os ocultos" do
      post render_preview_admin_landing_pages_path, params: { landing_page: { title: "Prévia", blocks_attributes: {
        "10" => block_params("text", { heading: "Segundo" }, position: 1),
        "11" => block_params("cover", { title: "Primeiro" }, position: 0),
        "12" => block_params("text", { heading: "Oculto" }, position: 2, visible: "0")
      } } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Primeiro", "Segundo")
      expect(response.body).not_to include("Oculto")
      expect(response.body.index("Primeiro")).to be < response.body.index("Segundo")
    end

    it "envolve cada bloco com a posição (a prévia é clicável); o site público não ganha o invólucro" do
      post render_preview_admin_landing_pages_path, params: { landing_page: { title: "P", blocks_attributes: { "0" => block_params("text", { heading: "A" }, position: 0), "1" => block_params("button", { label: "B", url: "/b" }, position: 1) } } }

      expect(Nokogiri::HTML(response.body).css(".lp-preview-block").map { |node| node["data-block-position"] }).to eq(%w[0 1])
    end

    it "mostra só imóveis da própria conta na vitrine" do
      mine = create(:habitation, tenant: tenant, exibir_no_site_flag: true, codigo: "MINE1")
      other = create(:habitation, tenant: Tenant.create!(name: "Outra", slug: "outra-#{SecureRandom.hex(3)}"), exibir_no_site_flag: true, codigo: "OTHER1")

      post render_preview_admin_landing_pages_path, params: { landing_page: { title: "V", blocks_attributes: { "0" => block_params("property_showcase", {}) } } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mine.codigo)
      expect(response.body).not_to include(other.codigo)
    end

    it "ignora id de bloco de outra conta" do
      foreign_page = Tenant.create!(name: "Outra", slug: "outra-#{SecureRandom.hex(3)}").landing_pages.create!(title: "Alheia", status: "published")
      foreign = foreign_page.blocks.create!(block_type: "text", data: { "heading" => "Segredo alheio" })

      post render_preview_admin_landing_pages_path(id: foreign_page.slug), params: { landing_page: { title: "X", blocks_attributes: { "0" => block_params("text", { heading: "Meu" }, id: foreign.id) } } }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Segredo alheio")
    end
  end

  describe "contagem de imóveis (endpoint legado do editor antigo)" do
    it "conta os imóveis mesmo com os campos vazios dos multiselects" do
      create(:habitation, tenant: tenant, exibir_no_site_flag: true)

      get "/admin/landing_pages/preview", params: { city: [""], neighborhood: [""], development: [""], category: [""], property_codes: [""], q: "", transaction_type: "" }, headers: { "Accept" => "application/json" }

      expect(JSON.parse(response.body)["count"]).to eq(1)
    end
  end

  it "lista as páginas com status e blocos" do
    page = tenant.landing_pages.create!(title: "Lista", status: "draft")
    page.blocks.create!(block_type: "text", data: { "heading" => "x" })

    get admin_landing_pages_path

    expect(response.body).to include("Lista", "Rascunho", "1 Texto")
  end
end
