require "rails_helper"

RSpec.describe "Registro global de modais", type: :request do
  let(:tenant) { Tenant.default }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  it "expõe cada modal ativo uma única vez com gatilho por #modal-<slug>" do
    form = PublicForm.ensure_default_announce_property!(tenant: tenant)
    other = tenant.public_forms.create!(
      name: "Parceria", slug: "parceria-x", category: "partnership",
      title: "Parceria", submit_label: "Enviar", success_message: "Ok"
    )

    get root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("body")["data-controller"]).to include("public-modal-trigger")
    [form, other].each do |modal|
      overlays = html.css("#modal-#{modal.slug}")
      expect(overlays.size).to eq(1), modal.slug
      expect(overlays.first["data-modal-slug"]).to eq(modal.slug)
    end
    # O do registro vem só com o overlay, sem botão próprio.
    registry_overlay = html.at_css("#modal-#{other.slug}")
    expect(registry_overlay.parent.at_xpath("./button")).to be_nil
  end

  it "aplica as cores do modal como variáveis CSS e ignora valores inválidos" do
    form = PublicForm.ensure_default_announce_property!(tenant: Tenant.default)
    form.update_columns(modal_config: form.modal_config.merge("aside_bg" => "#0a0b0c", "submit_bg" => "red;x:y"))

    get root_path

    html = Nokogiri::HTML(response.body)
    style = html.at_css("#modal-#{form.slug} .public-form-modal__dialog")["style"]
    expect(style).to include("--pfm-aside-bg:#0a0b0c")
    expect(style).not_to include("submit")
  end
end
