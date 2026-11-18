require "rails_helper"

RSpec.describe "Atribuição compartilhada dos formulários públicos", type: :request do
  let(:tenant) { Tenant.default }
  let(:form) { PublicForm.ensure_default_announce_property!(tenant: tenant) }
  let(:fields) do
    { name: "Maria Cliente", phone: "(47) 99999-0000", interest: "venda",
      city_state: "Itajaí/SC", property_details: "Apartamento" }
  end
  let(:attribution) do
    { utm_source: "tiktok", utm_medium: "cpc", ttclid: "last-click", utm_campaign: "retorno",
      landing_url: "https://site.example/retorno", first_touch: { gclid: "first-click" },
      conversion_touch: { ttclid: "last-click", utm_source: "tiktok", utm_medium: "cpc",
        utm_campaign: "retorno", landing_url: "https://site.example/retorno" } }
  end

  before do
    host! "localhost"
    allow(WebhookService).to receive(:send_form_data)
  end

  it "preserva atribuição e consentimento da submissão, sem transformá-la em conversão de aquisição" do
    cookies["unitymob_lgpd_consent"] = "accepted"
    cookies["_ga"] = "GA1.1.123.456"
    cookies["user_id_mh"] = "UID-cookie"
    post public_form_submissions_path(form.slug), params: {
      public_form_submission: fields, attribution: attribution,
      page_url: "https://site.example/formulario"
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).not_to have_key("analytics_event")
    source = form.submissions.last.source
    expect(source).to include("attribution_channel" => "tiktok_ads", "attribution_source" => "tiktok", "tracking_uid" => "UID-cookie")
    expect(source.fetch("attribution_data")).to include("ttclid" => "last-click", "utm_campaign" => "retorno",
      "analytics_consent" => "granted", "client_id" => "123.456", "tracking_uid" => "UID-cookie")
    expect(source.dig("attribution_data", "first_touch", "gclid")).to eq("first-click")
    expect(source.fetch("attribution_data")).not_to have_key("gclid")
    expect(WebhookService).to have_received(:send_form_data).with(form.webhook_origin,
      hash_including(attribution_data: source["attribution_data"], tracking_uid: "UID-cookie", "name" => "Maria Cliente"),
      hash_including(tenant: tenant, public_form: form))
  end

  it "mantém o contato no fluxo administrativo, sem lead nem distribuição" do
    cookies["unitymob_lgpd_consent"] = "accepted"
    contact = { name: "Contato Administrativo", email: "contato@example.test", phone: "(47) 99999-0000",
      message: "Gostaria de uma informação", interest_intent: "locar" }
    expect do
      expect do
        post contacts_path, params: { contact: contact, attribution: attribution }
      end.not_to have_enqueued_job(PublicFormLeadRoutingJob)
    end.not_to change(Lead, :count)

    expect(response).to redirect_to(root_path)
    expect(WebhookService).to have_received(:send_form_data).with("contact_form",
      hash_including("name" => contact[:name], "phone" => "5547999990000",
        lead_intent: "locar", lead_queue: "lead_locacao",
        "attribution_data" => hash_including("channel" => "tiktok_ads", "ttclid" => "last-click")),
      hash_including(request: an_instance_of(ActionDispatch::Request)))
  end

  it "aceita envio sem JavaScript e os campos de rastreamento legados sem mudar o destino" do
    post public_form_submissions_path(form.slug), params: {
      public_form_submission: fields.merge(utm_content: "legacy-uid"),
      page_url: "https://site.example/formulario?gbraid=legacy-click&utm_campaign=legada"
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(form.submissions.last.source.fetch("attribution_data")).to include(
      "gbraid" => "legacy-click", "utm_campaign" => "legada", "tracking_uid" => "legacy-uid", "channel" => "google_ads")
  end

  it "não aceita identidade, consentimento nem classificação declarados pelo formulário" do
    cookies["unitymob_lgpd_consent"] = "rejected"
    cookies["_ga"] = "GA1.1.123.456"
    post public_form_submissions_path(form.slug), params: { public_form_submission: fields,
      attribution: { client_id: "spoof", analytics_consent: "granted", channel: "meta_ads", tenant_id: 999,
        first_touch: "invalid", conversion_touch: { gclid: { bad: "value" }, fbp: "spoof" } },
      page_url: "javascript:invalid" }, as: :json

    expect(response).to have_http_status(:ok)
    data = form.submissions.last.source.fetch("attribution_data")
    expect(data).to include("analytics_consent" => "denied")
    expect(data.keys).not_to include("client_id", "fbp", "tenant_id", "gclid", "first_touch", "landing_url")
    expect(data["channel"]).not_to eq("meta_ads")
  end

  it "não alcança formulário de outra conta pelo slug nem aceita troca de tenant no payload" do
    other = Tenant.create!(name: "Outra atribuição", slug: "other-attribution-#{SecureRandom.hex(4)}")
    other_form = PublicForm.ensure_default_announce_property!(tenant: other)
    other_form.update!(slug: "exclusivo-outra-conta")
    expect do
      post public_form_submissions_path(other_form.slug), params: {
        public_form_submission: fields, attribution: attribution.merge(tenant_id: other.id)
      }, as: :json
    end.not_to change(PublicFormSubmission, :count)
    expect(response).to have_http_status(:not_found)
    expect(WebhookService).not_to have_received(:send_form_data)
  end

  it "captura no domínio de outra conta usando apenas formulário e destino dessa conta" do
    other = Tenant.create!(name: "Outra conta pública", slug: "public-attribution-#{SecureRandom.hex(4)}")
    hostname = "www.unitymob.com.br"
    TenantDomain.where(hostname: hostname).delete_all
    other.tenant_domains.create!(hostname: hostname, primary_domain: true)
    other_form = PublicForm.ensure_default_announce_property!(tenant: other)
    other_form.update!(webhook_url: "https://hooks.example.test/other")
    host! hostname
    expect do
      post public_form_submissions_path(other_form.slug), params: {
        public_form_submission: fields, attribution: attribution.merge(tenant_id: tenant.id)
      }, as: :json
    end.not_to change { form.submissions.count }

    expect(response).to have_http_status(:ok)
    expect(other_form.submissions.last).to have_attributes(tenant_id: other.id)
    expect(other_form.submissions.last.source["attribution_channel"]).to eq("tiktok_ads")
    expect(WebhookService).to have_received(:send_form_data).with(other_form.webhook_origin,
      hash_including(attribution_data: hash_including("channel" => "tiktok_ads")),
      hash_including(tenant: other, public_form: other_form, url: "https://hooks.example.test/other"))
  end
end
