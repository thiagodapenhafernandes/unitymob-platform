require "rails_helper"
require "open3"

RSpec.describe "Tracking tags", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "renderiza Google Tag Manager e Pixel da Meta no site publico quando ativos" do
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ID_KEY, "123456789012345")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_CONVERSION_ID_KEY, "AW-16492801046")
    Setting.set(TrackingIntegrationSetting::GOOGLE_SITE_VERIFICATION_TOKEN_KEY, "google_token-123")
    Setting.set(TrackingIntegrationSetting::RD_STATION_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::RD_STATION_LOADER_URL_KEY, "https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('meta name="google-site-verification" content="google_token-123"')
    expect(response.body).to include("https://www.googletagmanager.com/gtm.js?id=")
    expect(response.body).to include("https://www.googletagmanager.com/gtag/js?id=AW-16492801046")
    expect(response.body).to include('w.gtag("config", "AW-16492801046")')
    expect(response.body).to include("https://connect.facebook.net/en_US/fbevents.js")
    expect(response.body).to include('w.fbq("init", "123456789012345")')
    expect(response.body).to include("https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js")
  end

  it "nao renderiza tags de trackeamento no painel administrativo" do
    admin = create(:admin_user, :admin)
    sign_in admin

    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ID_KEY, "123456789012345")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_CONVERSION_ID_KEY, "AW-16492801046")
    Setting.set(TrackingIntegrationSetting::GOOGLE_SITE_VERIFICATION_TOKEN_KEY, "google_token-123")
    Setting.set(TrackingIntegrationSetting::RD_STATION_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::RD_STATION_LOADER_URL_KEY, "https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js")

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("googletagmanager.com/gtm.js")
    expect(response.body).not_to include("googletagmanager.com/gtag/js")
    expect(response.body).not_to include("connect.facebook.net/en_US/fbevents.js")
    expect(response.body).not_to include("google-site-verification")
    expect(response.body).not_to include("d335luupugsy2.cloudfront.net")
  end
  it "substitui o GTM pelo loader Stape e inclui a modalidade no clique" do
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    { stape_enabled: "true", stape_domain: "https://gtm.saluteimoveis.com.br",
      stape_loader_domain: "https://load.gtm.saluteimoveis.com.br", stape_identifier: "3ceniiuiwsxi",
      stape_configuration: "dxfrp44=ABC123" }.each { |field, value| Setting.set("tracking.#{field}", value) }
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://load.gtm.saluteimoveis.com.br", 'cookie("si_uid")', 'safari = safari && !!uid')
    expect(response.body).not_to include("https://www.googletagmanager.com/gtm.js", "https://www.googletagmanager.com/ns.html")
    expect(response.body).to include('negotiation_type: target.dataset.negotiationType || "general"')
  end

  it "aguarda o cookie mestre antes do loader e respeita recusa, revogação e falha de rede" do
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    { stape_enabled: "true", stape_domain: "https://gtm.saluteimoveis.com.br",
      stape_loader_domain: "https://load.gtm.saluteimoveis.com.br", stape_identifier: "3ceniiuiwsxi",
      stape_configuration: "dxfrp44=ABC123" }.each { |field, value| Setting.set("tracking.#{field}", value) }
    get root_path
    source = Nokogiri::HTML(response.body).css("script").find { |script| script.text.include?('var COOKIE_KEY = "unitymob_lgpd_consent"') }.text
    check = <<~JS
      const vm = require('node:vm'), assert = require('node:assert/strict');
      async function scenario({accepted = true, fail = false, withdraw = false} = {}) {
        let resolve, reject, requests = 0, cookie = '';
        const loaded = [], w = {location: {href: 'https://example.test'}, addEventListener() {}, UnitymobLgpdConsent: {accepted: () => accepted}};
        const d = {get cookie() {return cookie}, querySelector() {return null}, createElement() {return {}},
          head: {appendChild(script) {loaded.push(script.src)}}, addEventListener() {}};
        vm.runInNewContext(#{source.to_json}, {window:w, document:d, navigator:{userAgent:'Version/17.0 Safari/605.1'}, console,
          fetch() {requests++; return new Promise((ok, error) => {resolve = ok; reject = error})}});
        assert.equal(requests, accepted ? 1 : 0);
        assert.equal(loaded.length, 0);
        if (!accepted) return;
        if (withdraw) accepted = false;
        if (fail) reject(new Error('offline'));
        else {cookie = 'si_uid=stable-id'; resolve({ok:true})}
        await Promise.resolve(); await Promise.resolve();
        assert.equal(loaded.length, withdraw ? 0 : 1);
        if (!withdraw) assert.equal(loaded[0].includes('bi=stable-id'), !fail);
      }
      (async () => {await scenario({accepted:false}); await scenario(); await scenario({withdraw:true}); await scenario({fail:true})})()
        .catch(error => {console.error(error); process.exitCode = 1});
    JS
    _, error, status = Open3.capture3("node", "-e", check)
    expect(status.success?).to be(true), error
  end

  it "respeita recusa e mantém callback do GTM fora do payload da Meta" do
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    get root_path
    functions = response.body[/function trackingPayload\(eventName, payload\).*?(?=function closestTrackedClick)/m]
    script = <<~JS
      const assert = require('node:assert/strict');
      var accepted = false, meta = [];
      var w = {location: {href: 'https://example.test'}, fbq: (...args) => meta.push(args)};
      function consentAccepted() { return accepted; }
      #{functions}
      assert.equal(track('generate_lead', {}), false);
      assert.equal(w.dataLayer, undefined);
      accepted = true;
      var complete = () => {};
      assert.equal(track('generate_lead', {event_id: 'opaque', form_id: 'whatsapp_modal'}, {onComplete: complete}), true);
      assert.equal(w.dataLayer.length, 1);
      assert.equal(w.dataLayer[0].event_id, 'opaque');
      assert.equal(w.dataLayer[0].eventCallback, complete);
      assert.equal(w.dataLayer[0].eventTimeout, 500);
      assert.equal(meta[0][2].eventCallback, undefined);
    JS
    _, error, status = Open3.capture3("node", "-e", script)
    expect(status.success?).to be(true), error
  end

  it "padroniza o envelope do site e preserva aliases sem confundir ID interno com código" do
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    get root_path
    function = response.body[/function trackingPayload\(eventName, payload\).*?(?=function track\()/m]
    expect(function).to be_present
    script = "var w = {location: {href: 'https://example.test'}}; #{function}; console.log(JSON.stringify(['sale','rent','sale_rent','general'].map(type => trackingPayload('whatsapp_click', {negotiation_type:type, habitation_id:'23680', property_code:'AP1234'}))));"
    output, error, status = Open3.capture3("node", "-e", script)
    expect(status.success?).to be(true), error
    payloads = JSON.parse(output)
    expect(payloads.map { |data| data["business_type"] }).to eq(%w[venda locacao venda_locacao geral])
    expect(%w[sale rent sale_rent general].map { |value| Leads::Attribution.business_type(value) }).to eq(%w[venda locacao venda_locacao geral])
    payloads.each do |data|
      expect(data).to include("event" => "whatsapp_click", "event_name" => "whatsapp_click", "property_id" => "AP1234", "property_code" => "AP1234", "habitation_id" => "23680")
    end
    expect(payloads.map { |data| data["negotiation_type"] }).to eq(%w[sale rent sale_rent general])
  end

end
