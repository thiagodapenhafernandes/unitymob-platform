require "rails_helper"

RSpec.describe "Formulários nas páginas", type: :request do
  let(:tenant) { Tenant.default }
  let(:form) do
    tenant.public_forms.create!(name: "Contato", slug: "contato-bloco", category: "custom", title: "Fale conosco",
      submit_label: "Enviar", success_message: "Recebido", status: "published", modal_enabled: false).tap do |record|
      record.fields.create!(name: "email", label: "E-mail", field_type: "email", required: true, position: 0)
    end
  end

  it "exibe inline em todos os temas e usa o envio existente, mesmo sem modal habilitado" do
    page = tenant.landing_pages.create!(title: "Contato", slug: "pagina-contato", status: "published")
    block = page.blocks.create!(block_type: "form", position: 0, data: { form_id: form.id, form_style: "editorial", whatsapp_url: "https://wa.me/5547999999999", badge: "Análise jurídica inclusa" })
    host! "localhost"
    Tenant::PUBLIC_SITE_THEMES.each do |theme|
      tenant.update!(public_site_theme: theme)
      get public_landing_page_path(page.slug)
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      inline = html.at_css(".public-form-modal--inline")
      expect(inline).to be_present
      expect(inline["class"]).to include("public-form-modal--editorial")
      expect(inline.at_css("button[data-action='public-form-modal#whatsapp']")).to be_present
      expect(inline.at_css(".public-theme-builder-badge").text).to eq("Análise jurídica inclusa")
      expect(inline.at_css("[hidden].public-form-modal__overlay")).to be_nil
      expect(inline.at_css(".public-form-modal__close")).to be_nil
      expect(inline.at_css("form")["action"]).to eq(public_form_submissions_path(form.slug))
      expect(inline.at_css("label")["for"]).to eq("public_form_block-#{block.id}_email")
    end
    form.update!(status: "draft")
    get public_landing_page_path(page.slug)
    expect(Nokogiri::HTML(response.body).at_css(".public-form-modal--inline")).to be_nil
  end

  it "recusa formulário de outra conta ou não publicado" do
    page = tenant.landing_pages.new(title: "Contato")
    block = page.blocks.build(block_type: "form", position: 0, tenant: tenant, data: { form_id: form.id })
    expect(block).to be_valid
    foreign = Tenant.create!(name: "Outra conta", slug: "outra-conta-form")
    block.tenant = foreign
    expect(block.public_form).to be_nil
    expect(block).not_to be_valid
    block.tenant = tenant
    form.update!(status: "draft")
    expect(block).not_to be_valid
    block.data = { form_id: -1 }
    expect(block).not_to be_valid
    expect(block.data["form_id"]).to be_nil
  end
end
