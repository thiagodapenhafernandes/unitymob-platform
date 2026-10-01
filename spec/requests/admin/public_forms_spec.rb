require "rails_helper"

RSpec.describe "Admin Formulários: saída dos dados", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  it "salva webhook próprio e regra de distribuição do formulário" do
    form = PublicForm.ensure_default_announce_property!(tenant: admin.tenant)
    rule = create(:distribution_rule, tenant: admin.tenant)

    patch admin_public_form_path(form), params: {
      public_form: { webhook_url: "https://hooks.example.com/lead", distribution_rule_id: rule.id }
    }

    expect(response).to redirect_to(admin_public_form_path(form))
    expect(form.reload.webhook_url).to eq("https://hooks.example.com/lead")
    expect(form.distribution_rule_id).to eq(rule.id)
  end

  it "lista envios com filtros, 5 por página e link do lead" do
    form = PublicForm.ensure_default_announce_property!(tenant: admin.tenant)
    5.times do |i|
      form.submissions.create!(payload: { "name" => "Cliente #{i}", "email" => "c#{i}@example.com" }, source: { "page_url" => "https://site.example.com/" })
    end
    old = form.submissions.create!(payload: { "name" => "Antigo", "email" => "antigo@example.com" }, source: { "page_url" => "https://site.example.com/" })
    old.update_column(:created_at, 40.days.ago)
    lead = admin.tenant.leads.new(name: "Maria Cliente", phone: "5548999990000", origin: "test")
    lead.skip_automatic_routing = true
    lead.save!
    form.submissions.create!(payload: { "name" => "Maria Cliente", "email" => "maria@example.com" }, source: { "page_url" => "https://site.example.com/" }, lead: lead)

    get admin_public_form_path(form)
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css(".ax-table tbody tr").size).to eq(5)

    get admin_public_form_path(form), params: { page: 2 }
    expect(Nokogiri::HTML(response.body).css(".ax-table tbody tr").size).to eq(2)

    get admin_public_form_path(form), params: { q: "maria@example.com" }
    rows = Nokogiri::HTML(response.body).css(".ax-table tbody tr")
    expect(rows.size).to eq(1)
    expect(rows.first.at_css('a[href*="/admin/leads/"]')&.text).to eq("Ver lead")

    get admin_public_form_path(form), params: { period: "7" }
    expect(Nokogiri::HTML(response.body).text).not_to include("Antigo")
  end

  it "recusa URL inválida e regra de outra conta" do
    form = PublicForm.ensure_default_announce_property!(tenant: admin.tenant)
    other_rule = create(:distribution_rule)

    patch admin_public_form_path(form), params: {
      public_form: { webhook_url: "nota-url", distribution_rule_id: other_rule.id }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(form.reload.webhook_url).to be_nil
  end

  it "cria formulário com campo de anexo e guarda a config do arquivo" do
    post admin_public_forms_path, params: {
      public_form: {
        name: "Currículos", slug: "curriculos", category: "career", title: "Currículo", submit_label: "Enviar", success_message: "Ok",
        fields_attributes: {
          "0" => { field_type: "text", name: "name", label: "Nome", position: "10" },
          "1" => { field_type: "file", name: "cv", label: "Currículo", position: "20", required: "1",
                   config: { kind: "images", max_mb: "5", multiple: "1" } }
        }
      }
    }

    form = admin.tenant.public_forms.find_by!(slug: "curriculos")
    field = form.fields.find_by!(name: "cv")
    expect(field).to be_file_field
    expect(field.file_extensions).to include("png")
    expect(field.file_extensions).not_to include("pdf")
    expect(field.file_max_mb).to eq(5)
    expect(field.file_multiple?).to eq(true)
  end

  describe "preview do builder" do
    it "renderiza o modal com os dados não salvos, sem persistir nada" do
      expect do
        post preview_admin_public_forms_path, params: {
          public_form: {
            name: "Rascunho", slug: "rascunho", category: "custom", title: "Título do rascunho", submit_label: "Mandar", success_message: "Ok",
            modal_layout: "basic", modal_size: "large",
            fields_attributes: {
              "0" => { field_type: "text", name: "name", label: "Nome completo", position: "20" },
              "1" => { field_type: "file", name: "anexo", label: "Seu arquivo", position: "10", config: { kind: "documents", max_mb: "8" } },
              "2" => { field_type: "text", name: "removido", label: "Campo removido", position: "30", _destroy: "1" }
            }
          }
        }
      end.not_to change { [PublicForm.count, PublicFormField.count] }

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css(".public-form-modal__overlay")["hidden"]).to be_nil
      expect(html.at_css(".public-form-modal__dialog--basic.public-form-modal__dialog--size-large")).to be_present
      expect(html.css(".public-form-modal__field > label").map { |label| label.text.strip }).to eq(["Seu arquivo", "Nome completo"])
      expect(html.at_css("input[type=file]")["accept"]).to include(".pdf")
      dropzone = html.at_css(".public-file[data-controller='public-file-field']")
      expect(dropzone["data-public-file-field-max-mb-value"]).to eq("8")
      expect(dropzone.at_css("label.public-file__drop input.public-file__input[type=file]")).to be_present
      expect(dropzone.at_css(".public-file__hint").text).to include("até 8 MB")
      expect(response.body).to include("até 8 MB")
      expect(response.body).not_to include("Campo removido")
      # liga o preview ao card do builder (chaves de fields_attributes) e oferece "Adicionar campo"
      expect(html.css("[data-preview-field]").map { |field| field["data-preview-field"] }).to eq(%w[1 0])
      expect(html.at_css("button[data-preview-add]")).to be_present
    end

    it "exige permissão de admin" do
      sign_out admin
      post preview_admin_public_forms_path, params: { public_form: { name: "x" } }
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "tela guiada do builder" do
    it "organiza em etapas, com o ID do modal e todos os params do contrato" do
      get new_admin_public_form_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.css("[data-guided-step]").map { |step| step["data-guided-step"] }).to eq(%w[1 2 3 4 5 6 7])
      expect(html.at_css(".ax-guided-aside iframe[data-public-form-preview-target=frame]")).to be_present
      expect(html.at_css("[data-public-form-setup-target=anchor]").text).to start_with("#modal-")

      %w[name slug title subtitle submit_label success_message redirect_url webhook_url distribution_rule_id
         category status modal_enabled modal_layout modal_size].each do |param|
        expect(html.css("[name='public_form[#{param}]']")).not_to be_empty, "faltou public_form[#{param}]"
      end
      expect(html.css("input[name='public_form[modal_layout]']").map { |input| input["value"] }).to contain_exactly("premium", "basic")
      expect(html.css("[data-guided-step] > .ax-guided-step__body[hidden]").size).to eq(6)
    end

    it "abre o formulário existente para edição com o ID atual" do
      form = PublicForm.ensure_default_announce_property!(tenant: admin.tenant)

      get edit_admin_public_form_path(form)

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css("[data-public-form-setup-target=anchor]").text).to eq("#modal-#{form.slug}")
      expect(html.css("[data-public-form-builder-target=list] .public-form-builder__field").size).to eq(form.fields.count)
    end
  end

  describe "texto principal (Trix)" do
    let(:base_params) do
      { name: "Rico", slug: "rico", category: "custom", title: "Título", submit_label: "Enviar", success_message: "Ok" }
    end

    it "guarda só o HTML permitido e remove scripts e atributos perigosos" do
      post admin_public_forms_path, params: {
        public_form: base_params.merge(subtitle: '<div><strong>Olá</strong> <a href="javascript:alert(1)" onclick="x()">link</a><script>alert(1)</script></div>')
      }

      subtitle = admin.tenant.public_forms.find_by!(slug: "rico").subtitle
      expect(subtitle).to include("<strong>Olá</strong>")
      expect(subtitle).not_to include("script")
      expect(subtitle).not_to include("onclick")
      expect(subtitle).not_to include("javascript:")
    end

    it "trata o conteúdo vazio do Trix como sem texto principal" do
      post admin_public_forms_path, params: { public_form: base_params.merge(subtitle: "<div><br></div>") }

      expect(admin.tenant.public_forms.find_by!(slug: "rico").subtitle).to be_nil
    end

    it "mostra o editor Trix e o conteúdo do modal no bloco Tipo de modal" do
      get new_admin_public_form_path

      html = Nokogiri::HTML(response.body)
      expect(html.at_css("trix-editor[input=public_form_subtitle]")).to be_present
      expect(html.at_css("input#public_form_subtitle[name='public_form[subtitle]']")).to be_present
      expect(html.css("[data-guided-step='1'] label, [data-guided-step='1'] span.ax-label").map { |label| label.text.strip }).to include("Chamada", "Título", "Texto principal", "Benefícios")
      expect(html.css("[data-guided-step='2'] [name='public_form[subtitle]']")).to be_empty
      expect(response.body).to include("vendor/trix")
    end

    it "renderiza o texto formatado no preview, sanitizado" do
      post preview_admin_public_forms_path, params: {
        public_form: base_params.merge(modal_layout: "premium", subtitle: "<div><strong>Forte</strong><script>x()</script></div>",
                                       modal_config: { headline: "Meu título" })
      }

      html = Nokogiri::HTML(response.body)
      expect(html.at_css(".public-form-modal__aside h2").text).to eq("Meu título")
      expect(html.at_css(".public-form-modal__aside-subtitle strong").text).to eq("Forte")
      expect(response.body).not_to include("<script>x()")
    end
  end

  describe "preview editável e autosave" do
    let(:base) { { name: "Auto", slug: "auto", category: "custom", title: "Título", submit_label: "Enviar", success_message: "Ok" } }
    let(:json_headers) { { "Accept" => "application/json" } }

    it "guarda só cores #rrggbb no modal_config e descarta o resto" do
      post admin_public_forms_path, params: {
        public_form: base.merge(modal_config: { aside_bg: "#AABBCC", submit_bg: "red; background:url(x)", body_bg: "#12", aside_fg: "" })
      }

      config = admin.tenant.public_forms.find_by!(slug: "auto").modal_config
      expect(config["aside_bg"]).to eq("#aabbcc")
      expect(config.keys).not_to include("submit_bg", "body_bg", "aside_fg")
    end

    it "marca as regiões editáveis no preview e aplica as cores como variáveis CSS" do
      post preview_admin_public_forms_path, params: {
        public_form: base.merge(modal_layout: "premium", modal_config: { aside_bg: "#112233", submit_fg: "#ffffff" },
                                fields_attributes: { "0" => { field_type: "text", name: "name", label: "Nome", position: "10" } })
      }

      html = Nokogiri::HTML(response.body)
      expect(html.css("[data-edit]").map { |node| node["data-edit"] }).to include("aside", "eyebrow", "title", "subtitle", "body", "submit", "output")
      expect(html.at_css("[data-edit=title]")["data-bind"]).to eq("public_form[modal_config][headline]")
      expect(html.at_css("[data-edit=submit]")["data-bind"]).to eq("public_form[submit_label]")
      expect(html.at_css(".public-form-modal__dialog")["style"]).to include("--pfm-aside-bg:#112233", "--pfm-submit-fg:#ffffff")
      expect(html.at_css("[data-edit=output]").text).to include("webhook da conta")
    end

    it "no modelo Básico o título editável grava no título do formulário" do
      post preview_admin_public_forms_path, params: { public_form: base.merge(modal_layout: "basic") }

      expect(Nokogiri::HTML(response.body).at_css("[data-edit=title]")["data-bind"]).to eq("public_form[title]")
    end

    it "autosave cria o formulário em JSON e devolve o id de cada campo pela posição" do
      post admin_public_forms_path, headers: json_headers, params: {
        public_form: base.merge(fields_attributes: { "tok1" => { field_type: "text", name: "name", label: "Nome", position: "10" },
                                                     "tok2" => { field_type: "email", name: "email", label: "E-mail", position: "20" } })
      }

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      form = admin.tenant.public_forms.find_by!(slug: "auto")
      expect(body["update_url"]).to eq(admin_public_form_path(form))
      expect(body["edit_url"]).to eq(edit_admin_public_form_path(form))
      expect(body["fields"]).to eq(form.fields.to_h { |field| [field.position.to_s, field.id] })
    end

    it "autosave atualiza sem duplicar campos quando os ids voltam no envio" do
      form = admin.tenant.public_forms.create!(base.merge(status: "draft"))
      field = form.fields.create!(field_type: "text", name: "name", label: "Nome", position: 10)

      patch admin_public_form_path(form), headers: json_headers, params: {
        public_form: { title: "Novo título", modal_config: { aside_bg: "#010203" },
                       fields_attributes: { "0" => { id: field.id, label: "Nome completo", position: "10" } } }
      }

      expect(response).to have_http_status(:ok)
      expect(form.reload.title).to eq("Novo título")
      expect(form.modal_config["aside_bg"]).to eq("#010203")
      expect(form.fields.count).to eq(1)
      expect(field.reload.label).to eq("Nome completo")
    end

    it "autosave devolve os erros em JSON sem criar nada quando falta nome ou título" do
      expect do
        post admin_public_forms_path, headers: json_headers, params: { public_form: { name: "", title: "" } }
      end.not_to change(PublicForm, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["ok"]).to eq(false)
      expect(response.parsed_body["errors"]).not_to be_empty
    end

    it "traz os modelos das ferramentas e os campos de cor na tela" do
      get new_admin_public_form_path

      html = Nokogiri::HTML(response.body)
      expect(html.css("template[data-tool]").map { |node| node["data-tool"] }).to include("aside", "body", "eyebrow", "title", "subtitle", "submit", "benefits", "output", "field", "format")
      expect(html.css("input[name^='public_form[modal_config]'][data-color-text]").size).to eq(6)
      tools = html.at_css("[data-public-form-preview-target=tools]")
      expect(tools).to be_present
      # fixa a ferramenta enquanto o seletor de cor está em uso
      expect(tools["data-action"]).to include("focusin->public-form-preview#pinTools", "mouseleave->public-form-preview#toolsLeave", "mousemove->public-form-preview#toolsMove")
      expect(html.at_css("[data-public-form-preview-target=stage]")["data-action"]).to eq("mouseleave->public-form-preview#stageLeave")
      sizes = html.css("button[data-radio-name='public_form[modal_size]']")
      expect(sizes.map { |button| button["data-value"] }).to eq(PublicForm::MODAL_SIZES.keys)
      expect(sizes.select { |button| button["aria-pressed"] == "true" }.map { |button| button["data-value"] }).to eq(["xl"])
      expect(html.css("button[data-radio-name='public_form[modal_layout]']").map { |button| button["data-value"] }).to contain_exactly("premium", "basic")
      expect(html.css("select[data-radio-name]")).to be_empty

      devices = html.at_css("[aria-label='Dispositivo']").css("button").map { |button| button["data-device"] || "expandir" }
      expect(devices).to eq(%w[desktop mobile expandir])
      expect(html.at_css("[data-public-form-preview-target=fullscreenButton]")["data-action"]).to eq("public-form-preview#toggleFullscreen")
      expect(html.at_css("[data-public-form-preview-target=panel]")).to be_present

      stay = html.at_css("[data-public-form-preview-target=saveButton]")
      leave = html.at_css("[data-public-form-preview-target=saveExitButton]")
      expect([stay["type"], stay["data-action"]]).to eq(["button", "public-form-preview#saveNow"])
      expect(leave["type"]).to eq("submit")
    end
  end

  describe "status: inativo, rascunho e publicado" do
    let(:base) { { name: "Status", slug: "status-form", category: "custom", title: "Título", submit_label: "Enviar", success_message: "Ok" } }
    let(:json_headers) { { "Accept" => "application/json" } }

    it "abre o formulário novo como rascunho, com os três status para escolher" do
      get new_admin_public_form_path

      html = Nokogiri::HTML(response.body)
      expect(html.css("input[name='public_form[status]']").map { |input| input["value"] }).to contain_exactly("draft", "published", "inactive")
      expect(html.at_css("input[name='public_form[status]'][checked]")["value"]).to eq("draft")
      expect(html.at_css("form[data-controller~='public-form-preview']")["data-public-form-preview-saved-status-value"]).to eq("new")
    end

    it "publica só quando o status publicado é salvo de forma explícita" do
      post admin_public_forms_path, params: { public_form: base.merge(status: "draft") }
      form = admin.tenant.public_forms.find_by!(slug: "status-form")
      expect([form.status, form.active?]).to eq(["draft", false])

      patch admin_public_form_path(form), params: { public_form: { status: "published" } }
      expect([form.reload.status, form.active?]).to eq(["published", true])

      patch admin_public_form_path(form), params: { public_form: { status: "inactive" } }
      expect([form.reload.status, form.active?]).to eq(["inactive", false])
    end

    it "sem status no envio mantém o comportamento de antes (publicado)" do
      post admin_public_forms_path, params: { public_form: base }

      expect(admin.tenant.public_forms.find_by!(slug: "status-form")).to be_published
    end

    it "autosave cria sempre como rascunho, mesmo que peçam outro status" do
      post admin_public_forms_path, headers: json_headers, params: { public_form: base.merge(status: "published") }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["status"]).to eq("draft")
      expect(admin.tenant.public_forms.find_by!(slug: "status-form")).to be_draft
    end

    it "autosave em rascunho salva o conteúdo mas não muda o status" do
      form = admin.tenant.public_forms.create!(base.merge(status: "draft"))

      patch admin_public_form_path(form), headers: json_headers, params: { public_form: { title: "Só rascunho", status: "published" } }

      expect(response).to have_http_status(:ok)
      expect(form.reload.title).to eq("Só rascunho")
      expect(form).to be_draft
    end

    it "autosave recusa formulário publicado ou inativo e não altera nada" do
      %w[published inactive].each do |status|
        form = admin.tenant.public_forms.create!(base.merge(slug: "f-#{status}", name: "F #{status}", status: status))

        patch admin_public_form_path(form), headers: json_headers, params: { public_form: { title: "Alterado" } }

        expect(response).to have_http_status(:conflict), status
        expect(response.parsed_body["errors"].join).to include("Só rascunhos salvam sozinhos")
        expect(form.reload.title).to eq("Título")
      end
    end

    it "mostra o status na listagem" do
      admin.tenant.public_forms.create!(base.merge(status: "draft"))

      get admin_public_forms_path

      expect(response.body).to include("Rascunho")
    end

    it "mostra mensagens de erro do autosave com os nomes dos campos em português" do
      post admin_public_forms_path, headers: json_headers, params: { public_form: { name: "", title: "" } }

      errors = response.parsed_body["errors"].join(" · ")
      expect(errors).to include("Nome interno", "Título")
      expect(errors).not_to match(/\b(Name|Title|Slug)\b/)
    end
  end

  describe "formulário novo com conteúdo de exemplo" do
    it "abre como rascunho já com textos, benefícios e campos de exemplo" do
      get new_admin_public_form_path

      html = Nokogiri::HTML(response.body)
      expect(html.at_css("input[name='public_form[name]']")["value"]).to eq("Novo formulário")
      expect(html.at_css("input[name='public_form[slug]']")["value"]).to eq("novo-formulario")
      expect(html.at_css("input[name='public_form[title]']")["value"]).to eq("Título do formulário")
      expect(html.at_css("input[name='public_form[modal_config][eyebrow]']")["value"]).to eq("Chamada")
      expect(html.at_css("textarea[name='public_form[modal_config][headline]']").text.strip).to eq("Título da lateral")
      benefits = JSON.parse(html.at_css("input#public_form_benefits_json[name='public_form[modal_config][benefits]']")["value"])
      expect(benefits.map { |item| item["text"] }).to eq(["Benefício 1", "Benefício 2", "Benefício 3"])
      expect(benefits.map { |item| item["icon"] }.uniq).to eq(["bi-check-circle-fill"])
      expect(html.css("[data-controller='benefits-editor']").size).to eq(2) # bloco Tipo de modal + painel do preview
      expect(html.css("[data-public-form-builder-target=list] .public-form-builder__field").size).to eq(4)
      expect(html.at_css("input[name='public_form[status]'][checked]")["value"]).to eq("draft")
    end

    it "gera nome e ID únicos quando já existe um formulário de exemplo" do
      admin.tenant.public_forms.create!(name: "Novo formulário", slug: "novo-formulario", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok")

      get new_admin_public_form_path

      html = Nokogiri::HTML(response.body)
      expect(html.at_css("input[name='public_form[name]']")["value"]).to eq("Novo formulário 2")
      expect(html.at_css("input[name='public_form[slug]']")["value"]).to eq("novo-formulario-2")
    end

    it "o exemplo é válido: salvar sem mudar nada cria o rascunho com os quatro campos" do
      sample = PublicForm.build_sample(tenant: admin.tenant)

      expect(sample).to be_valid
      expect(sample.save).to eq(true)
      expect(sample.reload).to be_draft
      expect(sample.fields.pluck(:name)).to eq(%w[name email phone message])
    end
  end

  describe "benefícios com ícone" do
    let(:base) { { name: "Benef", slug: "benef", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok" } }
    let(:json) do
      [{ icon: "bi-star-fill", text: "Atendimento VIP" }, { icon: "bi-check-circle-fill", text: "Retorno rápido" },
       { icon: "bi-<script>", text: "Ícone inválido" }, { icon: "bi-key-fill", text: "   " }].to_json
    end

    it "salva texto + ícone, com o ícone padrão como texto simples, e descarta ícone inválido e linha vazia" do
      post admin_public_forms_path, params: { public_form: base.merge(modal_config: { benefits: json }) }

      saved = admin.tenant.public_forms.find_by!(slug: "benef").modal_config["benefits"]
      expect(saved).to eq([{ "text" => "Atendimento VIP", "icon" => "bi-star-fill" }, "Retorno rápido", "Ícone inválido"])
    end

    it "no preview cada benefício é um item com o seu ícone (e não um bloco só)" do
      post preview_admin_public_forms_path, params: { public_form: base.merge(modal_layout: "premium", modal_config: { benefits: json }) }

      items = Nokogiri::HTML(response.body).css(".public-form-modal__benefits li")
      expect(items.map { |item| item.at_css("span").text }).to eq(["Atendimento VIP", "Retorno rápido", "Ícone inválido"])
      expect(items.map { |item| item.at_css("i")["class"] }).to eq(["bi bi-star-fill", "bi bi-check-circle-fill", "bi bi-check-circle-fill"])
    end

    it "no preview, o texto antigo com uma linha por benefício também vira itens separados" do
      post preview_admin_public_forms_path, params: { public_form: base.merge(modal_layout: "premium", modal_config: { benefits: "Um\nDois\nTrês" }) }

      expect(Nokogiri::HTML(response.body).css(".public-form-modal__benefits li").size).to eq(3)
    end
  end

  describe "salvar e publicar sem sair (envio explícito em segundo plano)" do
    let(:base) { { name: "Explícito", slug: "explicito", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok" } }
    let(:json_headers) { { "Accept" => "application/json" } }

    it "publica um formulário em rascunho e devolve o status novo (commit=1)" do
      form = admin.tenant.public_forms.create!(base.merge(status: "draft"))

      patch admin_public_form_path(form), headers: json_headers, params: { commit: "1", public_form: { title: "Publicado", status: "published" } }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true, "status" => "published", "status_label" => "Publicado")
      expect(form.reload).to have_attributes(title: "Publicado", status: "published", active: true)
    end

    it "salva um formulário já publicado sem o bloqueio do autosave e permite inativar" do
      form = admin.tenant.public_forms.create!(base.merge(status: "published"))

      patch admin_public_form_path(form), headers: json_headers, params: { commit: "1", public_form: { title: "Novo título" } }
      expect(response).to have_http_status(:ok)
      expect(form.reload.title).to eq("Novo título")

      patch admin_public_form_path(form), headers: json_headers, params: { commit: "1", public_form: { status: "inactive" } }
      expect(form.reload).to have_attributes(status: "inactive", active: false)
    end

    it "sem commit continua valendo a regra do autosave (publicado responde 409)" do
      form = admin.tenant.public_forms.create!(base.merge(status: "published"))

      patch admin_public_form_path(form), headers: json_headers, params: { public_form: { title: "Não deve salvar" } }

      expect(response).to have_http_status(:conflict)
      expect(form.reload.title).to eq("T")
    end

    it "cria já publicado quando o salvamento explícito pede publicado" do
      post admin_public_forms_path, headers: json_headers, params: { commit: "1", public_form: base.merge(status: "published") }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["status"]).to eq("published")
      expect(admin.tenant.public_forms.find_by!(slug: "explicito")).to be_published
    end

    it "erros do salvamento explícito voltam em JSON, sem alterar o formulário" do
      form = admin.tenant.public_forms.create!(base.merge(status: "draft"))

      patch admin_public_form_path(form), headers: json_headers, params: { commit: "1", public_form: { title: "", status: "published" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to include("Título")
      expect(form.reload).to have_attributes(title: "T", status: "draft")
    end

    it "salvar e sair continua sendo o envio normal: aplica o status e redireciona" do
      form = admin.tenant.public_forms.create!(base.merge(status: "draft"))

      patch admin_public_form_path(form), params: { public_form: { status: "published" } }

      expect(response).to redirect_to(admin_public_form_path(form))
      expect(form.reload).to be_published
    end
  end

  describe "largura e máscara no builder" do
    let(:base) { { name: "Masc", slug: "masc", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok" } }

    it "salva largura e máscara do campo" do
      post admin_public_forms_path, params: {
        public_form: base.merge(fields_attributes: {
          "0" => { field_type: "text", name: "creci", label: "CRECI", position: "10", config: { width: "full", mask: "00000-A" } },
          "1" => { field_type: "text", name: "nome", label: "Nome", position: "20", config: { width: "auto", mask: "" } }
        })
      }

      fields = admin.tenant.public_forms.find_by!(slug: "masc").fields.index_by(&:name)
      expect(fields["creci"].config).to eq("width" => "full", "mask" => "00000-A")
      expect(fields["nome"].config).to eq({})
    end

    it "máscara inválida volta com erro em português e não salva" do
      expect do
        post admin_public_forms_path, headers: { "Accept" => "application/json" }, params: {
          public_form: base.merge(fields_attributes: { "0" => { field_type: "text", name: "x", label: "X", position: "10", config: { mask: "<b>" } } })
        }
      end.not_to change(PublicForm, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to include("Máscara")
    end

    it "traz largura e máscara no card, no mini editor e a largura na ferramenta do campo" do
      get new_admin_public_form_path

      html = Nokogiri::HTML(response.body)
      card = html.at_css("[data-public-form-builder-target=list] .public-form-builder__field")
      expect(card.at_css("select[name$='[config][width]']").css("option").map { |o| o["value"] }).to eq(%w[auto half full])
      expect(card.at_css("input[name$='[config][mask]']")).to be_present
      expect(card.css("[data-action='change->public-form-builder#maskPreset'] option").size).to eq(PublicFormField::MASK_PRESETS.size + 1)
      expect(html.at_css("[data-mode=editor] [data-proxy=width]")).to be_present
      expect(html.at_css("[data-mode=editor] [data-proxy=mask]")).to be_present
      expect(html.at_css("template[data-tool=field] [data-tool-action=width]")).to be_present
    end

    it "o preview marca a largura efetiva de cada campo para a ferramenta alternar" do
      post preview_admin_public_forms_path, params: {
        public_form: base.merge(fields_attributes: {
          "0" => { field_type: "text", name: "a", label: "A", position: "10" },
          "1" => { field_type: "text", name: "b", label: "B", position: "20", config: { width: "full" } }
        })
      }

      classes = Nokogiri::HTML(response.body).css("[data-preview-field]").map { |node| node["class"][/--w-(\w+)/, 1] }
      expect(classes).to eq(%w[half full])
    end
  end

  describe "aviso do link do modal no editor" do
    it "formulário novo (rascunho) já mostra o aviso; publicado e disponível para modal, não" do
      get new_admin_public_form_path
      warning = Nokogiri::HTML(response.body).at_css("[data-public-form-setup-target=linkWarning]")
      expect(warning).to be_present
      expect(warning["hidden"]).to be_nil

      form = admin.tenant.public_forms.create!(name: "No ar", slug: "no-ar", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok", status: "published")
      get edit_admin_public_form_path(form)
      expect(Nokogiri::HTML(response.body).at_css("[data-public-form-setup-target=linkWarning]")["hidden"]).not_to be_nil
    end
  end

  describe "filtro dos envios" do
    it "usa a barra de filtros em linha: busca, período e botão lado a lado" do
      form = PublicForm.ensure_default_announce_property!(tenant: admin.tenant)

      get admin_public_form_path(form)

      bar = Nokogiri::HTML(response.body).at_css("form.ax-filter-bar")
      expect(bar).to be_present
      expect(bar.element_children.map { |node| [node.name, node["class"].to_s.split.first] }.first(3)).to eq([%w[input ax-search], %w[select ax-control], %w[button ax-btn]])
      expect(bar.at_css("select[name=period]").css("option").map { |o| o["value"] }).to eq(["", "7", "30"])
    end
  end
end
