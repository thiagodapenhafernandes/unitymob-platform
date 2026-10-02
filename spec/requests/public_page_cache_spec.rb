require "rails_helper"

RSpec.describe "Cache de página pública (home)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { Tenant.default }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:mode) { "on" }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    allow(Rails).to receive(:cache).and_return(store)
    Setting.set(PublicPageCache::MODE_SETTING_KEY, mode, tenant:)
    tenant.home_sections.create!(section_type: :cta_contact, title: "Vamos conversar?", active: true, order_position: 1)
    ContactSetting.instance(tenant:).update!(whatsapp_primary: "(47) 99123-4567")
    # O primeiro acesso de uma conta cria a SeoSetting da home (rastreador de SEO) e sobe a versão uma vez.
    get root_path
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def cache_status = response.headers["X-Public-Page-Cache"]

  def csrf_token = Nokogiri::HTML(response.body).at_css("meta[name='csrf-token']")&.[]("content")

  context "ligado" do
    it "serve o segundo acesso do cache, com o mesmo conteúdo e token CSRF próprio de cada visitante" do
      allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)
      get root_path
      expect(response).to have_http_status(:ok)
      expect(cache_status).to eq("miss")
      first_body = response.body
      first_token = csrf_token

      get root_path
      expect(cache_status).to eq("hit")
      expect(response.body).not_to include(PublicPageCache::CSRF_PLACEHOLDER)
      expect(csrf_token).to be_present
      expect(csrf_token).not_to eq(first_token)
      expect(PublicPageCache.normalize(response.body)).to eq(PublicPageCache.normalize(first_body))
    end

    it "mostra na hora a mudança feita no admin (configuração de contato)" do
      get root_path
      get root_path
      expect(cache_status).to eq("hit")
      expect(response.body).to include("5547991234567")

      ContactSetting.instance(tenant:).update!(whatsapp_primary: "(47) 98888-7777")

      get root_path
      expect(cache_status).to eq("miss")
      expect(response.body).to include("5547988887777")
      expect(response.body).not_to include("5547991234567")
    end

    it "renova quando um imóvel é salvo e quando uma seção da home muda" do
      property = create(:habitation, tenant:, exibir_no_site_flag: true)
      get root_path
      get root_path
      expect(cache_status).to eq("hit")

      property.update!(valor_venda_cents: property.valor_venda_cents.to_i + 100)
      get root_path
      expect(cache_status).to eq("miss")

      get root_path
      expect(cache_status).to eq("hit")
      tenant.home_sections.first.update!(title: "Outro título")
      get root_path
      expect(cache_status).to eq("miss")
    end

    it "separa as variantes de consentimento LGPD" do
      get root_path
      get root_path
      expect(cache_status).to eq("hit")

      cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"
      get root_path
      expect(cache_status).to eq("miss")
      get root_path
      expect(cache_status).to eq("hit")
    end

    it "não usa cache com query string" do
      get root_path
      get root_path, params: { utm_source: "teste" }
      expect(cache_status).to be_nil
    end

    it "expira em até 10 minutos mesmo sem nenhuma mudança (rede de segurança)" do
      get root_path
      get root_path
      expect(cache_status).to eq("hit")

      travel(PublicPageCache::MAX_AGE + 1.minute) do
        get root_path
        expect(cache_status).to eq("miss")
      end
    end

    it "continua registrando a visita de SEO (com consentimento) quando serve do cache" do
      cookies[ApplicationController::LGPD_CONSENT_COOKIE] = "accepted"
      get root_path
      expect(SeoSetting.find_by(tenant:, canonical_key: "home")).to be_present

      seo = SeoSetting.find_by!(tenant:, canonical_key: "home")
      expect { get root_path }.to change { seo.reload.access_count.to_i }.by(1)
      expect(cache_status).to eq("hit")
      expect(SeoPageVisit.where(seo_setting: seo).sum(:visits_count)).to be >= 2
    end

    it "não deixa a contagem de acessos da SEO (register_access!) invalidar a página" do
      get root_path
      get root_path
      expect(cache_status).to eq("hit")

      SeoSetting.find_by!(tenant:, canonical_key: "home").register_access!

      get root_path
      expect(cache_status).to eq("hit")
    end

    it "invalida quando o SEO da home muda de fato" do
      get root_path
      get root_path
      expect(cache_status).to eq("hit")

      SeoSetting.find_by!(tenant:, canonical_key: "home").update!(meta_title: "Título novo da home")

      get root_path
      expect(cache_status).to eq("miss")
      expect(response.body).to include("Título novo da home")
    end
  end

  context "desligado (padrão)" do
    let(:mode) { "off" }

    it "não usa nem grava cache" do
      get root_path
      get root_path
      expect(cache_status).to be_nil
      expect(response).to have_http_status(:ok)
    end
  end

  context "modo sombra" do
    let(:mode) { "shadow" }

    it "renderiza sempre e só registra que o cacheado confere" do
      allow(Rails.logger).to receive(:info).and_call_original
      allow(Rails.logger).to receive(:warn).and_call_original
      get root_path
      get root_path

      expect(cache_status).to eq("shadow-compared")
      expect(Rails.logger).to have_received(:info).with(/\[public_page_cache\]\[shadow\] igual/)
      expect(Rails.logger).not_to have_received(:warn).with(/DIVERGENCIA/)
    end

    it "loga divergência quando o conteúdo muda sem que a versão suba" do
      get root_path
      ContactSetting.where(tenant_id: tenant.id).update_all(whatsapp_primary: "(47) 90000-0000") # update_all não dispara callbacks
      allow(Rails.logger).to receive(:warn).and_call_original

      get root_path

      expect(Rails.logger).to have_received(:warn).with(/\[public_page_cache\]\[shadow\] DIVERGENCIA/)
    end
  end
end
