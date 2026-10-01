require "rails_helper"

RSpec.describe "shared/_public_form_modal.html.erb", type: :view do
  def build_form(tenant, **attrs)
    tenant.public_forms.create!(
      { name: "Captação", slug: "captacao", category: "custom",
        title: "Captação", submit_label: "Enviar", success_message: "Ok" }.merge(attrs)
    ).tap do |form|
      form.fields.create!(field_type: "text", name: "name", label: "Nome", position: 10)
    end
  end

  it "renderiza o Premium com lateral, tamanho e ID âncora" do
    tenant = Tenant.create!(name: "Conta PM #{SecureRandom.hex(3)}", slug: "conta-pm-#{SecureRandom.hex(3)}")
    form = build_form(tenant, modal_layout: "premium", modal_size: "large")

    render("shared/public_form_modal", form: form, trigger_label: "Abrir", trigger_class: "btn")

    overlay = Nokogiri::HTML(rendered).at_css(".public-form-modal__overlay")
    expect(overlay["id"]).to eq("modal-captacao")
    expect(overlay["data-modal-slug"]).to eq("captacao")
    dialog = overlay.at_css(".public-form-modal__dialog")
    expect(dialog["class"]).to include("premium", "size-large")
    expect(dialog.at_css(".public-form-modal__aside")).to be_present
    expect(dialog.at_css("form")).to be_present
  end

  it "renderiza o Básico só com formulário" do
    tenant = Tenant.create!(name: "Conta BM #{SecureRandom.hex(3)}", slug: "conta-bm-#{SecureRandom.hex(3)}")
    form = build_form(tenant, modal_layout: "basic", modal_size: "small")

    render("shared/public_form_modal", form: form, trigger_label: "Abrir", trigger_class: "btn")

    dialog = Nokogiri::HTML(rendered).at_css(".public-form-modal__dialog")
    expect(dialog["class"]).to include("basic", "size-small")
    expect(dialog.at_css(".public-form-modal__aside")).to be_nil
    expect(dialog.at_css("form")).to be_present
  end

  it "cobre layouts e tamanhos nas duas variantes de CSS" do
    base = File.read(Rails.root.join("app/assets/stylesheets/components/_public_form_modal.scss"))
    luxury = File.read(Rails.root.join("app/assets/stylesheets/public_site_themes/salute_luxury.css"))

    %w[--basic --size-small --size-default --size-large --size-xl --size-fullscreen].each do |modifier|
      expect(base).to include(".public-form-modal__dialog#{modifier}"), "base #{modifier}"
      expect(luxury).to include(".public-form-modal__dialog#{modifier}"), "luxury #{modifier}"
    end
  end

  describe "largura e máscara dos campos" do
    let(:tenant) { Tenant.create!(name: "Conta MK #{SecureRandom.hex(3)}", slug: "conta-mk-#{SecureRandom.hex(3)}") }
    let(:form) do
      build_form(tenant, slug: "mascaras").tap do |record|
        record.fields.create!(field_type: "text", name: "creci", label: "CRECI", position: 20, config: { "mask" => "00000-A", "width" => "full" })
        record.fields.create!(field_type: "tel", name: "phone", label: "Telefone", position: 30, config: { "mask" => "(00) 00000-0000" })
        record.fields.create!(field_type: "tel", name: "fone2", label: "Telefone 2", position: 40)
        record.fields.create!(field_type: "currency", name: "valor", label: "Valor", position: 50)
        record.fields.create!(field_type: "textarea", name: "msg", label: "Mensagem", position: 60, config: { "width" => "half" })
      end
    end

    def html_for(form)
      render("shared/public_form_modal", form: form, trigger_label: "Abrir", trigger_class: "btn")
      Nokogiri::HTML(rendered)
    end

    it "marca a largura de cada campo (automática, inteira e meia)" do
      html = html_for(form)
      widths = html.css(".public-form-modal__field").to_h { |node| [node.at_css("input, textarea")["name"], node["class"][/--w-(\w+)/, 1]] }

      expect(widths).to include(
        "public_form_submission[name]" => "half", "public_form_submission[creci]" => "full", "public_form_submission[msg]" => "half"
      )
    end

    it "campo com máscara vira texto com input-mask, padrão de validação, dica e tamanho" do
      html = html_for(form)
      creci = html.at_css("input[name='public_form_submission[creci]']")

      expect(creci["type"]).to eq("text")
      expect(creci["data-controller"]).to eq("input-mask")
      expect(creci["data-input-mask-pattern-value"]).to eq("00000-A")
      expect(creci["pattern"]).to eq('\d\d\d\d\d-[A-Za-z]')
      expect(creci["maxlength"]).to eq("7")
      expect(creci["inputmode"]).to eq("text")
      expect(creci["placeholder"]).to eq("00000-A")
      expect(creci["title"]).to eq("Formato: 00000-A")
    end

    it "telefone com máscara usa a máscara; sem máscara continua com o campo de telefone com país" do
      html = html_for(form)

      masked = html.at_css("input[name='public_form_submission[phone]']")
      expect([masked["data-controller"], masked["inputmode"]]).to eq(["input-mask", "numeric"])
      expect(html.at_css("input[name='public_form_submission[fone2]']")["data-controller"]).to eq("phone-input")
    end

    it "moeda usa o modo dinheiro sem precisar configurar" do
      valor = html_for(form).at_css("input[name='public_form_submission[valor]']")

      expect(valor["data-input-mask-pattern-value"]).to eq("money")
      expect(valor["placeholder"]).to eq("R$ 0,00")
      expect(valor["maxlength"]).to be_nil
    end
  end
end
