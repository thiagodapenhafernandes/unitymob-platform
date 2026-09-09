require "rails_helper"

RSpec.describe MetaLeadEnrichmentJob, type: :job do
  let(:integration) { create(:user_meta_integration, ad_account_id: "123456") }
  let(:tenant) { integration.tenant }
  let(:lead) { create(:lead, tenant: tenant, attribution_channel: "meta_ads", attribution_data: {"ad_id" => "987654"}, other_information: {"keep" => "original"}) }
  let(:service) { instance_double(Facebook::MetaService) }

  before do
    allow(Facebook::MetaService).to receive(:new).with(integration.access_token).and_return(service)
    allow(service).to receive(:ad_details).with("987654").and_return({"id" => "987654", "account_id" => "123456", "name" => "Anúncio", "campaign" => {"id" => "234567", "name" => "Campanha oficial"}, "adset" => {"id" => "345678", "name" => "Conjunto"}})
  end

  it "salva nomes confirmados sem modificar responsável/status e não repete a consulta" do
    original = lead.attributes.slice("admin_user_id", "status")
    2.times { described_class.perform_now(tenant.id, lead.id) }
    expect(lead.reload.other_information).to include("keep" => "original", "meta_campaign_name" => "Campanha oficial", "meta_ad_name" => "Anúncio")
    expect(lead.attributes.slice("admin_user_id", "status")).to eq(original)
    expect(service).to have_received(:ad_details).once
  end

  it "não grava anúncio de outra conta" do
    allow(service).to receive(:ad_details).and_return({"id" => "987654", "account_id" => "999999"})
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.other_information).to eq("keep" => "original")
  end

  it "não procura lead fora do tenant" do
    other = Tenant.create!(name: "Outra conta", slug: "meta-other")
    described_class.perform_now(other.id, lead.id)
    expect(service).not_to have_received(:ad_details)
  end

  it "não deduz IDs a partir de utm_campaign" do
    lead.update_columns(attribution_data: {"utm_campaign" => "6953"})
    described_class.perform_now(tenant.id, lead.id)
    expect(service).not_to have_received(:ad_details)
    expect(lead.reload.other_information).not_to have_key("meta_enriched_at")
  end

  it "não escolhe arbitrariamente entre conexões" do
    create(:user_meta_integration, tenant: tenant, ad_account_id: "555555")
    described_class.perform_now(tenant.id, lead.id)
    expect(service).not_to have_received(:ad_details)
  end

  it "usa o formulário sincronizado da integração" do
    page = create(:meta_facebook_page, user_meta_integration: integration)
    form = create(:meta_lead_form, meta_facebook_page: page, form_id: "765432", name: "Formulário oficial")
    lead.update_columns(other_information: {"meta_form_id" => form.form_id})
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.other_information["meta_form_name"]).to eq("Formulário oficial")
  end

  it "agenda retry quando a API falha e não marca sucesso" do
    allow(service).to receive(:ad_details).and_raise(Koala::Facebook::APIError.new(503, nil, {"code" => 2, "message" => "Temporary"}))
    lead
    expect { described_class.perform_now(tenant.id, lead.id) }.to have_enqueued_job(described_class)
    expect(lead.reload.other_information).not_to have_key("meta_enriched_at")
  end

  it "enfileira o trabalho para o novo lead" do
    expect { lead }.to have_enqueued_job(described_class).with(tenant.id, anything)
  end
end
