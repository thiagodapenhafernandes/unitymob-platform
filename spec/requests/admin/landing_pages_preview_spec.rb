require "rails_helper"

RSpec.describe "Prévia salva de páginas", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:page) { tenant.landing_pages.create!(title: "Página em revisão", slug: "pagina-revisao", status: "draft") }

  before do
    host! "localhost"
    sign_in admin
    page.blocks.create!(tenant: tenant, block_type: "cover", position: 0, data: { title: "Conteúdo em revisão" })
  end

  it "mantém a estrutura da página real no editor em todos os temas, inclusive seções vazias" do
    [["section", { columns: 2 }], ["text", { body: "Primeira coluna", column: "1" }],
     ["text", { body: "Segunda coluna", column: "2" }],
     ["callout", { heading: "Linha inteira", layout_width: "page" }],
     ["section", { columns: 2 }]].each_with_index do |(type, data), index|
      page.blocks.create!(tenant: tenant, block_type: type, position: index + 1, data: data)
    end
    Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
      tenant.update_columns(public_site_theme: theme)
      get page_preview_admin_landing_page_path(page)
      original = Nokogiri::HTML(response.body).at_css(".public-landing-page")
      blocks = page.blocks.order(:position).each_with_index.to_h { |block, index| [index.to_s, block.attributes.slice("id", "block_type", "position", "visible", "data")] }
      post render_preview_admin_landing_pages_path, params: { id: page.id, landing_page: { title: page.title, layout_columns: page.layout_columns, blocks_attributes: blocks } }
      expect(response).to have_http_status(:ok)
      edited = Nokogiri::HTML(response.body).at_css(".public-landing-page")
      expect(edited.css(".lp-preview-block").size).to eq(page.blocks.count)
      expect(edited.css(".lp-preview-block")).to all(satisfy { |node| node["class"].include?("public-theme-block-layout") })
      edited.css(".lp-preview-block").each do |node|
        node["class"] = node["class"].split.reject { |name| name == "lp-preview-block" }.join(" ")
        node.remove_attribute("data-block-position")
      end
      expect(edited.to_html).to eq(original.to_html), "Estrutura diferente no tema #{theme}"
    end
  end

  it "recebe estilos compactados na prévia e no salvamento com a mesma validação" do
    block = page.blocks.first
    data = { title: "Título atualizado", element_title_font_family: "georgia", element_title_background_mode: "transparent", element_title_text_gradient: true, element_title_text_color: "#123456", element_title_text_gradient_color: "#abcdef", unknown_style: "display:none" }
    attrs = { "0" => { id: block.id, block_type: "cover", position: 0, visible: true, data_payload: data.to_json } }
    post render_preview_admin_landing_pages_path, params: { id: page.id, landing_page: { title: page.title, blocks_attributes: attrs } }
    expect(response).to have_http_status(:ok)
    title = Nokogiri::HTML(response.body).at_css("[data-element-field='title']")
    expect(title['style']).to include("font-family:Georgia,serif", "background-clip:text")
    patch admin_landing_page_path(page), params: { landing_page: { blocks_attributes: attrs } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(block.reload.data).to include("element_title_font_family" => "georgia", "element_title_text_gradient" => true)
    expect(block.data).not_to have_key("unknown_style")
    attrs["0"][:data_payload] = "[1,2]"
    post render_preview_admin_landing_pages_path, params: { landing_page: { blocks_attributes: attrs } }
    expect(response).to have_http_status(:bad_request)
  end

  it "oferece prévia de rascunho em nova aba na listagem" do
    get admin_landing_pages_path
    link = Nokogiri::HTML(response.body).at_css("a[href='#{page_preview_admin_landing_page_path(page)}']")
    expect(link.text).to include("Pré-visualizar")
    expect(link["target"]).to eq("_blank")
    expect(link["rel"]).to include("noopener")
  end

  it "renderiza o rascunho sem publicá-lo e sem permitir cache ou indexação" do
    get page_preview_admin_landing_page_path(page)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conteúdo em revisão", "public-site-theme--#{tenant.public_site_theme_key}")
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    expect(page.reload).to be_draft
  end

  it "não permite prévia de página de outra conta" do
    other = Tenant.create!(name: "Outra conta", slug: "outra-conta-preview").landing_pages.create!(title: "Outra conta", slug: "outra-conta", status: "draft")
    get page_preview_admin_landing_page_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it "oferece prévia em nova aba na barra do editor de rascunhos" do
    get edit_admin_landing_page_path(page)
    link = Nokogiri::HTML(response.body).at_css("[data-landing-page-builder-target='openPreview']")
    expect(link.text).to include("Abrir prévia")
    expect(link["href"]).to eq(page_preview_admin_landing_page_path(page))
    expect(link["target"]).to eq("_blank")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("form.lp-canvas-editor")).to be_present
    expect(html.css("[data-action='landing-page-builder#openInspector']").map { |el| el['data-inspector'] }).to eq(%w[add structure page seo])
    expect(html.css("[data-landing-page-builder-target='inspectorTitle']").size).to eq(1)
  end

  it "abre o mesmo builder na prévia sem o restante do admin" do
    get page_preview_admin_landing_page_path(page, editing: "1")
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("form.lp-fullscreen-editor input[name='editor_mode']")["value"]).to eq("preview")
    expect(html.at_css("[data-landing-page-builder-target='frame']")).to be_present
    expect(response.body).to include("Visualizar", "landing-page-builder#openInspector")
    expect(page.reload).to be_draft
  end

  it "mantém o salvamento manual no modo de edição da prévia" do
    patch admin_landing_page_path(page), params: { editor_mode: "preview", continue: "1", landing_page: { title: "Título revisado" } }
    expect(response).to redirect_to(page_preview_admin_landing_page_path(page, editing: "1"))
    expect(page.reload.title).to eq("Título revisado")
    expect(page).to be_draft
  end

  it "salvar e sair retorna à visualização e erros mantêm o editor" do
    patch admin_landing_page_path(page), params: { editor_mode: "preview", landing_page: { title: "Título revisado" } }
    expect(response).to redirect_to(page_preview_admin_landing_page_path(page))
    patch admin_landing_page_path(page), params: { editor_mode: "preview", continue: "1", landing_page: { title: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("lp-fullscreen-editor", "editor_mode")
  end

  it "oferece ativar edição sem ferramentas na visualização" do
    get page_preview_admin_landing_page_path(page)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("a[href='#{page_preview_admin_landing_page_path(page, editing: '1')}']").text).to eq("Ativar edição")
    expect(html.at_css("form.lp-canvas-editor")).to be_nil
  end

  it "não abre o editor em tela inteira para outra conta" do
    other = Tenant.create!(name: "Outra conta", slug: "outra-conta-editor").landing_pages.create!(title: "Outra", slug: "outra", status: "draft")
    get page_preview_admin_landing_page_path(other, editing: "1")
    expect(response).to have_http_status(:not_found)
  end

  it "oferece Trix nas respostas e mantém o índice de perguntas vazias na prévia" do
    page.blocks.create!(tenant: tenant, block_type: "faq", position: 1, data: { items: [{ title: "", text: "Ainda em revisão" }, { title: "Pergunta visível", text: "<strong>Resposta formatada</strong>" }] })
    get page_preview_admin_landing_page_path(page, editing: "1")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("trix-editor[input$='_text__input']")).to be_present
    expect(html.at_css(".lp-inspector-resize")).to be_present
    get page_preview_admin_landing_page_path(page)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("[data-faq-row-index='1']").text).to include("Pergunta visível")
    expect(html.at_css("[data-faq-row-index='1'] strong").text).to eq("Resposta formatada")
  end

  it "exige autenticação" do
    sign_out admin
    get page_preview_admin_landing_page_path(page)
    expect(response).to have_http_status(:redirect)
  end
  it "mantém estilos independentes e etiquetas adicionáveis na capa" do
    cover = page.blocks.first
    cover.update!(data: { title: "Título", subtitle: "Introdução", eyebrow: "Etiqueta original",
      element_subtitle_custom_colors: true, element_subtitle_background_color: "#112233", element_subtitle_text_color: "#ffffff",
      element_eyebrow_custom_border: true, element_eyebrow_border_radius: 24,
      labels: [{ title: "Nova etiqueta", custom_colors: true, background_color: "#445566", text_color: "#ffffff", custom_border: true, border_radius: 12, border_style: "solid", border_color: "#778899", border_width: 2 }] })
    get page_preview_admin_landing_page_path(page)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("[data-element-field='subtitle']")["style"]).to include("background-color:#112233", "color:#ffffff")
    expect(doc.at_css("[data-element-field='title']")["style"].to_s).not_to include("#112233")
    expect(doc.at_css("[data-element-field='eyebrow']")["style"]).to include("border-radius:24px")
    expect(doc.at_css("[data-label-index='0']")["style"]).to include("#445566", "border-radius:12px")
    get page_preview_admin_landing_page_path(page, editing: 1)
    expect(response.body).to include("Adicionar etiqueta", "element_subtitle_text_color", 'data-block-field="image_desktop"')
  end

end
