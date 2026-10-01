require "rails_helper"

RSpec.describe "Admin Site público: identidade, topo e contato", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  describe "Identidade" do
    it "reúne marca, paleta e modelo visual em seções navegáveis" do
      get edit_admin_public_identity_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      tabs = html.css(".ax-studio-nav [data-ax-tabs-target='tab']").map { |tab| tab["data-ax-tabs-target-param"] }
      expect(tabs).to eq(%w[#identity-tab-brand #identity-tab-colors #identity-tab-theme #identity-tab-settings])
      expect(html.css("select[name='tenant[public_site_theme]'] option").map { |option| option["value"] }).to eq(%w[default])
      expect(html.at_css("input[name='layout_setting[primary_color]']")).to be_present
      expect(html.at_css("input[type='file'][name='layout_setting[logo]']")).to be_present
      expect(html.at_css(".ax-studio__aside .lss-web")).to be_present
    end

    it "salva marca, paleta e modelo visual apenas da conta autenticada" do
      other_tenant = Tenant.create!(name: "Outra marca #{SecureRandom.hex(3)}", slug: "outra-marca-#{SecureRandom.hex(3)}")

      patch admin_public_identity_path, params: {
        layout_setting: { site_name: "Marca Nova", primary_color: "#112233", secondary_color: "#223344", accent_color: "#334455" },
        tenant: { public_site_theme: "default" }
      }

      expect(response).to redirect_to(edit_admin_public_identity_path)
      setting = LayoutSetting.instance(tenant: admin.tenant).reload
      expect(setting).to have_attributes(site_name: "Marca Nova", primary_color: "#112233", accent_color: "#334455")
      expect(other_tenant.reload.public_site_theme).to eq("default")
    end

    it "oferece só o Padrão e o modelo da própria identidade, nunca o de outro cliente" do
      admin.tenant.update!(name: "Salute Imóveis", slug: "salute-#{SecureRandom.hex(3)}")

      get edit_admin_public_identity_path

      values = Nokogiri::HTML(response.body).css("select[name='tenant[public_site_theme]'] option").map { |option| option["value"] }
      # Os dois modelos da marca, identificada pelo nome da conta.
      expect(values).to eq(%w[default saluteimoveis salute_luxury])
      expect(response.body).not_to include("Conexão Imobiliária")

      patch admin_public_identity_path, params: { layout_setting: { site_name: "X" }, tenant: { public_site_theme: "conexaoimobiliaria" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(admin.tenant.reload.public_site_theme).to eq("saluteimoveis")
    end

    it "não deixa a conta gravar um modelo inexistente" do
      patch admin_public_identity_path, params: { layout_setting: { site_name: "X" }, tenant: { public_site_theme: "inexistente" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(admin.tenant.reload.public_site_theme).not_to eq("inexistente")
    end

    it "exige a permissão do Site público" do
      profile = Profile.create!(tenant: admin.tenant, name: "Só dashboard #{SecureRandom.hex(3)}", axis: "vertical", position: 8_761,
                                permissions: { "dashboard" => { "view" => true } })
      sign_out admin
      sign_in create(:admin_user, tenant: admin.tenant, profile: profile)

      get edit_admin_public_identity_path
      expect(response).to redirect_to(admin_root_path)
      patch admin_public_header_path, params: { home_setting: { header_cta_label: "X" } }
      expect(response).to redirect_to(admin_root_path)
    end

    it "deixa em Conta só a aparência da plataforma" do
      get edit_admin_layout_setting_path

      expect(response.body).to include("Aparência da plataforma")
      expect(response.body).not_to include("layout_setting[logo]", "layout_setting[primary_color]", "layout_setting[site_name]")
    end
  end

  describe "Topo e menu" do
    it "lista os itens do sistema na ordem original com a barra do desktop marcada" do
      get edit_admin_public_header_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      keys = html.css(".hm-rows .hm-row input[name$='[key]']").map { |option| option["value"] }
      expect(keys).to eq(PublicHeaderMenu::SYSTEM_ITEMS.keys)
      bar = html.css(".hm-rows .hm-row").select { |row| row.at_css("input[type='checkbox'][name$='[bar]']")["checked"] }.map { |row| row.at_css("input[name$='[key]']")["value"] }
      expect(bar).to eq(%w[comprar alugar anunciar empreendimentos lancamentos blog favoritos])
    end

    it "renderiza cartões colapsáveis com resumo, edição e exclusão" do
      patch admin_public_header_path, params: {
        home_setting: {
          header_menu: {
            "0" => { key: "alugar", position: "1", label: "", visible: "1", bar: "1" },
            "1" => { key: "custom-a1", custom: "1", position: "2", label: "Condomínios", url: "/condominios", visible: "1", bar: "0" }
          }
        }
      }

      get edit_admin_public_header_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      container = html.at_css(".hm-rows[data-controller='header-menu-sort']")
      expect(container).to be_present
      rows = container.css("details.hm-row[data-menu-row]")
      expect(rows).not_to be_empty
      rows.each do |row|
        head = row.at_css("summary.hm-row__head")
        expect(head.at_css(".hm-row__handle")).to be_present
        expect(head.at_css("[data-role='title']").text).not_to be_empty
        expect(head.at_css("[data-role='dest']")).to be_present
        expect(row.at_css("button[data-action='nested-form#moveUp']")).to be_nil
        body = row.at_css(".hm-row__body")
        expect(body.at_css("input[type='hidden'][data-role='position']")).to be_present
        expect(body.at_css("input[data-role='label']")).to be_present
        expect(body.at_css("button[data-action='nested-form#remove']")).to be_present
      end
      custom = rows.detect { |row| row.at_css("input[data-role='custom']")["value"] == "1" }
      system = rows.detect { |row| row.at_css("input[data-role='custom']")["value"] == "0" }
      expect(custom.at_css("input[data-role='url']")).to be_present
      # Qualquer item é editável: o do sistema também tem endereço (vazio = padrão da página) e nova aba.
      system_url = system.at_css("input[data-role='url']")
      expect(system_url).to be_present
      expect(system_url["disabled"]).to be_nil
      expect(system_url["readonly"]).to be_nil
      expect(system_url["name"]).to match(/\[url\]\z/)
      expect(system_url["placeholder"]).to start_with("/")
      expect(system_url["value"]).to be_blank
      expect(system.at_css("input[type='checkbox'][name$='[new_tab]']")).to be_present
      expect(system.at_css(".hm-row__body input[disabled][readonly]")).to be_nil
    end

    it "grava ordem, rótulos, visibilidade, link próprio e botão" do
      patch admin_public_header_path, params: {
        home_setting: {
          header_cta_label: "Agende uma visita", header_cta_url: "/contato",
          header_menu: {
            "0" => { key: "alugar", position: "1", label: "Locação", visible: "1", bar: "1" },
            "1" => { key: "comprar", position: "2", label: "", visible: "0", bar: "0" },
            "2" => { key: "custom-a1", custom: "1", position: "3", label: "Condomínios", url: "https://exemplo.com/condominios", visible: "1", bar: "1", new_tab: "1" },
            "3" => { key: "custom-b2", custom: "1", position: "4", label: "Perigo", url: "javascript:alert(1)", visible: "1", bar: "1" },
            "4" => { key: "blog", position: "5", label: "", visible: "1", bar: "0", _destroy: "1" }
          }
        },
        contact_setting: { show_phone_in_header: "1" }
      }

      expect(response).to redirect_to(edit_admin_public_header_path)
      home = HomeSetting.instance(tenant: admin.tenant).reload
      expect(home.header_cta_label).to eq("Agende uma visita")
      expect(home.header_menu).to eq([
        { "key" => "alugar", "label" => "Locação", "visible" => true, "bar" => true },
        { "key" => "comprar", "visible" => false, "bar" => false },
        { "key" => "custom-a1", "custom" => true, "label" => "Condomínios", "url" => "https://exemplo.com/condominios", "visible" => true, "bar" => true, "new_tab" => true }
      ])
      expect(ContactSetting.instance(tenant: admin.tenant).show_phone_in_header).to be(true)
    end

    it "deixa trocar o endereço de um item do sistema por #modal-ID e o link sai no topo do site" do
      patch admin_public_header_path, params: {
        home_setting: {
          header_menu: {
            "0" => { key: "trabalhe", position: "1", label: "", url: "#modal-trabalhe-conosco", visible: "1", bar: "1", new_tab: "0" }
          }
        }
      }

      expect(response).to redirect_to(edit_admin_public_header_path)
      saved = HomeSetting.instance(tenant: admin.tenant).reload.header_menu.first
      expect(saved).to include("key" => "trabalhe", "url" => "#modal-trabalhe-conosco", "bar" => true)

      get edit_admin_public_header_path
      row = Nokogiri::HTML(response.body).css(".hm-rows .hm-row").detect { |node| node.at_css("input[name$='[key]']")["value"] == "trabalhe" }
      expect(row.at_css("input[data-role='url']")["value"]).to eq("#modal-trabalhe-conosco")
      expect(row.at_css("input[data-role='url']")["placeholder"]).to eq(Rails.application.routes.url_helpers.trabalhe_conosco_path)
      expect(row.at_css("[data-role='dest']").text.strip).to eq("#modal-trabalhe-conosco")

      get root_path
      link = Nokogiri::HTML(response.body).css("a").detect { |a| a["href"] == "#modal-trabalhe-conosco" && a.text.include?("Trabalhe conosco") }
      expect(link).to be_present
    end

    it "endereço inválido num item do sistema é ignorado e a página volta ao padrão" do
      patch admin_public_header_path, params: {
        home_setting: { header_menu: { "0" => { key: "trabalhe", position: "1", label: "", url: "javascript:alert(1)", visible: "1", bar: "0" } } }
      }

      saved = HomeSetting.instance(tenant: admin.tenant).reload.header_menu.first
      expect(saved).not_to include("url")
    end

    it "recusa destino do botão que não seja página ou endereço válido" do
      patch admin_public_header_path, params: { home_setting: { header_cta_url: "javascript:alert(1)" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "salva o número do topo junto do toggle sem vazar outro tenant" do
      other = Tenant.create!(name: "Outra topo #{SecureRandom.hex(3)}", slug: "outra-topo-#{SecureRandom.hex(3)}")
      ContactSetting.instance(tenant: other).update!(phone: "+5511311112222")

      patch admin_public_header_path, params: {
        contact_setting: { phone: "(48) 99999-0000", show_phone_in_header: "1" }
      }

      expect(response).to redirect_to(edit_admin_public_header_path)
      expect(ContactSetting.instance(tenant: admin.tenant).reload.phone).to eq("5548999990000")
      expect(ContactSetting.instance(tenant: other).reload.phone).to eq("5511311112222")
    end

    it "espelha a barra real com fone resolvido e drawer" do
      ContactSetting.instance(tenant: admin.tenant).update!(phone: "+554832220000", show_phone_in_header: true)
      LayoutSetting.instance(tenant: admin.tenant).logo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")),
        filename: "logo.png", content_type: "image/png"
      )

      get edit_admin_public_header_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css(".hps-workspace")["data-theme-variant"]).to eq("default")
      expect(html.at_css(".hps-theme")&.text).to include("Padrão", "Trocar em Identidade")
      header = html.at_css(".hm-web .hps-header")
      expect(header["class"]).not_to include("luxury")
      expect(header.at_css(".hps-header__logo")).to be_present
      expect(header.at_css(".hps-header__search")).to be_present
      expect(header.at_css(".hps-header__toggle")).to be_present
      expect(header.at_css(".hps-header__cta")&.text).to include("Fale Conosco")
      expect(header.at_css(".hps-header__links")["data-header-menu-preview-target"]).to eq("bar")
      expect(header.css(".hps-header__link")).not_to be_empty
      phone = header.at_css(".hps-header__phone")
      expect(phone.key?("hidden")).to be(false)
      expect(phone.text).to include("55 (48) 3222-0000")
      expect(html.at_css('input[name="contact_setting[phone]"]')["data-live-text"]).to eq("phone")
      expect(html.text).to include("do Telefone fixo")
      panel = html.at_css(".hm-web__panel")
      expect(panel.at_css(".hm-web__panel-cta")&.text).to include("Fale Conosco")
      expect(panel.at_css(".hm-web__panel-phone").key?("hidden")).to be(false)
    end

    it "renderiza logo SVG sem variant na prévia" do
      LayoutSetting.instance(tenant: admin.tenant).logo.attach(
        io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
        filename: "logo.svg", content_type: "image/svg+xml"
      )

      get edit_admin_public_header_path

      expect(response).to have_http_status(:ok)
      logo = Nokogiri::HTML(response.body).at_css(".hps-header__logo")
      expect(logo["src"]).to include("blobs")
    end

    it "resolve o fone do WhatsApp e ignora o toggle no drawer" do
      ContactSetting.instance(tenant: admin.tenant).update!(
        phone: nil, whatsapp_primary: "+5548999990000", show_phone_in_header: false
      )

      get edit_admin_public_header_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css(".hm-web .hps-header__phone").key?("hidden")).to be(true)
      panel_phone = html.at_css(".hm-web__panel-phone")
      expect(panel_phone.key?("hidden")).to be(false)
      expect(panel_phone.text).to include("55 (48) 99999-0000")
      expect(panel_phone.at_css(".bi-whatsapp")).to be_present
      expect(html.text).to include("do WhatsApp principal")
    end

    it "liga as 4 cores do topo no hover real da prévia" do
      get edit_admin_public_header_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      {
        "home_setting[header_menu_color]" => "--hps-h-menu",
        "home_setting[header_menu_hover_color]" => "--hps-h-hover",
        "home_setting[header_cta_background]" => "--hps-h-cta",
        "home_setting[header_cta_hover_background]" => "--hps-h-cta-hover"
      }.each do |name, var|
        expect(html.at_css(%(input[name="#{name}"][data-live-var="#{var}"]))).to be_present, name
      end
      expect(html.css(".hps-header__link--hover")).to be_empty
      stylesheet = File.read(Rails.root.join("app/assets/stylesheets/admin/components/home_studio.css"))
      expect(stylesheet).to include(".hps-header__link:hover", ".hps-header__cta:hover")
    end

    it "apaga a aparência e tira o CTA da barra no luxury" do
      admin.tenant.update!(public_site_theme: "salute_luxury")
      ContactSetting.instance(tenant: admin.tenant).update!(phone: "+554832220000", show_phone_in_header: true)

      get edit_admin_public_header_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css(".hps-workspace")["data-theme-variant"]).to eq("salute-luxury")
      header = html.at_css(".hm-web .hps-header")
      expect(header["class"]).to include("luxury")
      expect(header.at_css(".hps-header__cta")).to be_nil
      expect(header.at_css(".hps-header__search")).to be_nil
      expect(html.at_css(".hm-web__panel-cta")).to be_present
      expect(html.text).to include("só no menu em tela cheia")
      expect(html.css(".ax-studio-group.hps-limited .hps-limited__note")).not_to be_empty
      expect(html.at_css("details.ax-studio-advanced.hps-limited")).to be_present
    end
  end

  describe "Contato" do
    it "unifica canais, roteamento do WhatsApp e mensagens numa tela só" do
      get edit_admin_contact_setting_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      tabs = html.css(".ax-studio-nav [data-ax-tabs-target='tab']").map { |tab| tab["data-ax-tabs-target-param"] }
      expect(tabs).to eq(%w[#contact-tab-channels #contact-tab-forms #contact-tab-social])
      WhatsappBusinessIntegration::NEGOTIATION_TYPES.each_value do |config|
        expect(html.at_css("input[name='whatsapp_business_integration[#{config[:phone_attribute]}]']")).to be_present
      end
      expect(html.at_css("textarea[name='contact_setting[sale_whatsapp_message]']")).to be_present
      expect(response.body).to include("Para onde vai cada lead")
    end

    it "salva contato e destinos do WhatsApp juntos" do
      patch admin_contact_setting_path, params: {
        contact_setting: { whatsapp_primary: "554733111067", sale_whatsapp_message: "Olá {nome}" },
        whatsapp_business_integration: {
          default_whatsapp_number: "554733111067", sale_whatsapp_number: "5547991111111", rent_whatsapp_number: "5547992222222",
          rent_requires_lead_form: "0", rent_redirect_after_capture: "0"
        }
      }

      expect(response).to redirect_to(edit_admin_contact_setting_path)
      expect(ContactSetting.instance(tenant: admin.tenant).sale_whatsapp_message).to eq("Olá {nome}")
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      expect(integration.phone_for("sale")).to eq("5547991111111")
      expect(integration.requires_form_for?("rent")).to be(false)
    end

    it "redireciona a antiga aba Telefones do site de Integrações" do
      get admin_whatsapp_integration_path(tab: "site_phones")

      expect(response).to redirect_to(edit_admin_contact_setting_path)
    end
  end

  describe "cabeçalho público" do
    it "renderiza o menu personalizado no site" do
      home = HomeSetting.instance(tenant: admin.tenant)
      home.update!(header_cta_label: "Agende agora", header_cta_url: "/simulador-financiamento",
                   header_menu: PublicHeaderMenu.normalize({ "0" => { key: "alugar", label: "Locação", visible: "1", bar: "1" },
                                                             "1" => { key: "comprar", visible: "0" },
                                                             "2" => { key: "custom-x", custom: "1", label: "Condomínios", url: "/condominios", visible: "1", bar: "1" } }))
      Tenants::LocalPublicHostOverride.activate!(admin.tenant)
      host! Tenants::LocalPublicHostOverride::HOST

      get root_path

      header = Nokogiri::HTML(response.body).at_css("header[data-public-header]")
      bar = header.css("[data-header-part='links'] a").map { |link| link.text.squish }
      expect(bar.first(2)).to eq(%w[Locação Condomínios])
      expect(bar).not_to include("Comprar")
      cta = header.at_css("[data-header-part='cta']")
      expect([cta.text.squish, cta["href"]]).to eq(["Agende agora", "/simulador-financiamento"])
    end
  end

  describe "Topo: aviso de destino #modal-ID sem modal no site" do
    before do
      admin.tenant.public_forms.create!(name: "Fale conosco", slug: "fale-conosco", category: "custom", title: "T",
                                        submit_label: "Enviar", success_message: "Ok", status: "draft")
    end

    it "avisa no botão do topo quando o formulário está em rascunho" do
      patch admin_public_header_path, params: { home_setting: { header_cta_label: "Fale Conosco", header_cta_url: "#modal-fale-conosco" } }

      get edit_admin_public_header_path

      hint = Nokogiri::HTML(response.body).at_css("input[name='home_setting[header_cta_url]']").ancestors(".ax-field").first.text
      expect(hint).to include("Fale conosco", "Rascunho", "publique")
    end

    it "avisa na linha do menu e some depois de publicar" do
      patch admin_public_header_path, params: {
        home_setting: { header_menu: { "0" => { key: "trabalhe", position: "1", label: "", url: "#modal-fale-conosco", visible: "1", bar: "1" } } }
      }

      get edit_admin_public_header_path
      expect(Nokogiri::HTML(response.body).css(".hm-row__warn").map(&:text).join).to include("Rascunho")

      admin.tenant.public_forms.find_by!(slug: "fale-conosco").update!(status: "published")
      get edit_admin_public_header_path
      expect(Nokogiri::HTML(response.body).css(".hm-row__warn")).to be_empty
    end
  end
end
