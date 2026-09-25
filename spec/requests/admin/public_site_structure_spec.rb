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
      expect(tabs).to eq(%w[#identity-tab-brand #identity-tab-colors #identity-tab-theme])
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
      expect(values).to eq(%w[default saluteimoveis])
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
      expect(system.at_css("input[data-role='url']")).to be_nil
      expect(system.at_css(".hm-row__body input[disabled][readonly]")).to be_present
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

    it "recusa destino do botão que não seja página ou endereço válido" do
      patch admin_public_header_path, params: { home_setting: { header_cta_url: "javascript:alert(1)" } }

      expect(response).to have_http_status(:unprocessable_entity)
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
end
