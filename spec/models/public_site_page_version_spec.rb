require "rails_helper"

RSpec.describe PublicSite::PageVersion do
  let(:tenant) { Tenant.default }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  def version = described_class.current(tenant.id)

  it "mantém a versão estável até alguém chamar bump" do
    expect(version).to be_present
    expect(version).to eq(version)

    expect { described_class.bump(tenant.id) }.to change { version }
  end

  it "volta a ter versão (miss, nunca conteúdo velho) se o cache perder a chave" do
    old = version
    store.clear
    expect(version).to be_present
    expect(version).not_to eq(old)
  end

  describe "registros que aparecem no site" do
    it "sobem a versão ao confirmar a gravação" do
      { "contato" => -> { ContactSetting.instance(tenant:).update!(whatsapp_primary: "(47) 90000-1111") },
        "tenant" => -> { tenant.update!(name: "#{tenant.name} ") },
        "link do rodapé" => -> { FooterSetting.instance(tenant:).footer_links.create!(label: "Sobre", url: "/sobre") },
        "configuração de tracking" => -> { Setting.set("tracking.meta_pixel.pixel_id", "123", tenant: tenant) } }.each do |nome, mudanca|
        expect { mudanca.call }.to change { version }, "#{nome} deveria subir a versão"
      end
    end

    it "não sobem com estado operacional de sincronização" do
      version
      expect { Setting.set("dwv_sync_status", "running", tenant: tenant) }.not_to change { version }
      expect { Setting.set("seo_discovery_status", "ok", tenant: tenant) }.not_to change { version }
    end

    it "só sobe com o SEO da home e só quando o conteúdo muda (contadores e outras páginas não contam)" do
      home = SeoSetting.find_or_create_by!(tenant:, page_name: "home") { |seo| seo.canonical_key = "home"; seo.meta_title = "Home" }
      other = SeoSetting.find_or_create_by!(tenant:, page_name: "imoveis") { |seo| seo.canonical_key = "imoveis"; seo.meta_title = "Imóveis" }
      version

      expect { home.register_access! }.not_to change { version }
      expect { other.update!(meta_title: "Imóveis #{SecureRandom.hex(3)}") }.not_to change { version }
      expect { home.update!(meta_title: "Home #{SecureRandom.hex(3)}") }.to change { version }
    end

    it "sobem quando um imóvel é salvo, excluído ou tem foto anexada (touch)" do
      property = create(:habitation, tenant:, exibir_no_site_flag: true)
      version

      expect { property.update!(valor_venda_cents: property.valor_venda_cents.to_i + 1) }.to change { version }
      expect { property.touch }.to change { version }
      expect { property.destroy! }.to change { version }
    end
  end

  it "inclui o concern em todos os modelos que a home lê" do
    models = %w[HomeSetting LayoutSetting ContactSetting FooterSetting FooterLink FooterSocialLink FooterStore Store Banner SeoSetting
                PublicForm PublicFormField WhatsappBusinessIntegration WebhookSetting HomeSection HomeSectionItem TenantDomain
                BlogCategory LandingPage Tenant Setting].map(&:constantize)

    expect(models.reject { |model| model.include?(PublicSite::BumpsPageVersion) }).to be_empty
  end
end
