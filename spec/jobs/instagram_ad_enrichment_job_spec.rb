require "rails_helper"

RSpec.describe Instagram::AdEnrichmentJob, type: :job do
  include ActiveJob::TestHelper
  let(:integration) { create(:user_meta_integration, ad_account_id: "123456") }
  let(:tenant) { integration.tenant }
  let(:page) { create(:meta_facebook_page, user_meta_integration: integration, instagram_id: "12345", instagram_enabled: true) }
  let(:event) do
    { "sender" => { "id" => "98765" }, "recipient" => { "id" => "12345" },
      "timestamp" => 1_789_000_000_000, "message" => { "mid" => "paid-1", "text" => "Tenho interesse",
        "referral" => { "source" => "ADS", "type" => "OPEN_THREAD", "ad_id" => "987654" } } }
  end
  let(:graph) { instance_double(Koala::Facebook::API) }
  let(:ad) do
    { "id" => "987654", "account_id" => "123456", "name" => "Anúncio A",
      "campaign" => { "id" => "234567", "name" => "Campanha A" }, "adset" => { "id" => "345678", "name" => "Conjunto A" } }
  end

  before do
    integration.update!(selected_page_ids: [page.page_id])
    allow(Koala::Facebook::API).to receive(:new).with(integration.access_token).and_return(graph)
    allow(graph).to receive(:get_object).with("987654", fields: "id,name,account_id,campaign{id,name},adset{id,name}").and_return(ad)
  end

  def receive_event
    InstagramDirectJob.perform_now(page.instagram_id, event)
    tenant.leads.find_by!(instagram_account_id: page.instagram_id, instagram_scoped_id: event.dig("sender", "id"))
      .instagram_messages.find_by!(message_id: event.dig("message", "mid"))
  end

  it "enriquece a mensagem e complementa somente a primeira origem, com execução idempotente" do
    message = receive_event
    lead = message.lead.reload
    previous = lead.attributes.except("other_information")
    initial_entry = lead.other_information.fetch("instagram_entry").deep_dup
    expect(enqueued_jobs).to include(hash_including(job: described_class, args: [tenant.id, lead.id, message.id]))

    2.times { described_class.perform_now(tenant.id, lead.id, message.id) }

    data = message.reload.context.fetch("ad_attribution")
    expect(data).to include("meta_ad_name" => "Anúncio A", "meta_campaign_name" => "Campanha A", "meta_adset_name" => "Conjunto A", "meta_ad_account_id" => "123456")
    expect(lead.reload.other_information["instagram_entry"]).to eq(initial_entry.merge("ad_attribution" => data))
    expect(lead.attributes.except("other_information")).to eq(previous)
    expect(graph).to have_received(:get_object).once
  end

  it "mantém a origem orgânica e os dados confirmados do cliente quando uma campanha chega depois" do
    event["message"].delete("referral")
    first = receive_event
    lead = first.lead
    lead.update!(name: "Nome confirmado", email: "cliente@example.test", phone: "5547999991234", origin: "Site")
    previous = lead.reload.attributes
    first_attributes = first.attributes
    clear_enqueued_jobs
    event["message"] = { "mid" => "paid-2", "text" => "Novo anúncio", "referral" => { "ad_id" => "987654" } }
    second = receive_event

    described_class.perform_now(tenant.id, lead.id, second.id)

    expect(second.reload.context.dig("ad_attribution", "meta_campaign_name")).to eq("Campanha A")
    expect(lead.reload.attributes).to eq(previous)
    expect(first.reload.attributes).to eq(first_attributes)
  end

  it "não substitui a primeira campanha com outra mensagem de mídia" do
    first = receive_event
    lead = first.lead
    described_class.perform_now(tenant.id, lead.id, first.id)
    initial_info = lead.reload.other_information.deep_dup
    first_context = first.reload.context.deep_dup
    event["message"]["mid"] = "paid-2"
    event["message"]["referral"]["ad_id"] = "876543"
    second = receive_event
    allow(graph).to receive(:get_object).with("876543", fields: "id,name,account_id,campaign{id,name},adset{id,name}")
      .and_return(ad.merge("id" => "876543", "name" => "Anúncio B", "campaign" => { "id" => "456789", "name" => "Campanha B" }))

    described_class.perform_now(tenant.id, lead.id, second.id)

    expect(second.reload.context.dig("ad_attribution", "meta_campaign_name")).to eq("Campanha B")
    expect(first.reload.context).to eq(first_context)
    expect(lead.reload.other_information).to eq(initial_info)
  end

  it "não reprocessa duplicatas nem agenda mensagens orgânicas, enviadas ou históricas" do
    first = receive_event
    clear_enqueued_jobs
    InstagramDirectJob.perform_now(page.instagram_id, event)
    first.update!(context: first.context.merge("note" => "Atualização local"))
    first.lead.instagram_messages.create!(message_id: "legacy", body: "Anterior", occurred_at: 2.days.ago, context: { "referral" => { "ad_id" => "987654" } })
    first.lead.instagram_messages.create!(message_id: "out", direction: "outbound", occurred_at: Time.current, context: first.context)
    event["message"] = { "mid" => "organic", "text" => "Olá" }
    receive_event

    expect(enqueued_jobs.none? { |job| job[:job] == described_class }).to be(true)
  end

  it "ignora ID inválido e conta de anúncios fora da seleção" do
    event["message"]["referral"]["ad_id"] = "invalid/path"
    message = receive_event
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(graph).not_to have_received(:get_object)
    event["message"] = { "mid" => "foreign-ad", "text" => "Olá", "referral" => { "ad_id" => "987654" } }
    message = receive_event
    allow(graph).to receive(:get_object).and_return(ad.merge("account_id" => "555555"))
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(message.reload.context).not_to have_key("ad_attribution")
  end

  it "recusa uma resposta com outro ID de anúncio, mesmo na conta selecionada" do
    message = receive_event
    allow(graph).to receive(:get_object).and_return(ad.merge("id" => "111111"))
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(message.reload.context).not_to have_key("ad_attribution")
  end

  it "usa apenas a integração da página que recebeu o evento, mesmo com outras conexões no tenant" do
    create(:user_meta_integration, tenant: tenant, ad_account_id: "555555", access_token: "other-token")
    message = receive_event
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(message.reload.context.dig("ad_attribution", "meta_ad_name")).to eq("Anúncio A")
    expect(Koala::Facebook::API).not_to have_received(:new).with("other-token")
  end

  it "não acessa mensagem de outro lead ou tenant" do
    message = receive_event
    other = Tenant.create!(name: "Outra", slug: "ig-ad-other-#{SecureRandom.hex(4)}")
    described_class.perform_now(other.id, message.lead_id, message.id)
    another = create(:lead, tenant: tenant)
    described_class.perform_now(tenant.id, another.id, message.id)
    expect(graph).not_to have_received(:get_object)
  end

  it "não aceita uma página de outro tenant inserida no contexto" do
    message = receive_event
    foreign = create(:user_meta_integration, tenant: Tenant.create!(name: "Outra página", slug: "ig-page-#{SecureRandom.hex(4)}"))
    foreign_page = create(:meta_facebook_page, user_meta_integration: foreign, instagram_enabled: true, instagram_id: "54321")
    message.update_columns(context: message.context.merge("meta_facebook_page_id" => foreign_page.id))
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(graph).not_to have_received(:get_object)
  end

  it "recusa página desativada, removida da seleção ou que mudou de perfil" do
    message = receive_event
    page.update!(instagram_enabled: false)
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    page.update!(instagram_enabled: true, instagram_id: "54321")
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    page.update!(instagram_id: "12345")
    integration.update!(selected_page_ids: [])
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(graph).not_to have_received(:get_object)
  end

  it "recusa token expirado e revalida a seleção depois da consulta" do
    message = receive_event
    integration.update!(token_expires_at: 1.minute.ago)
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(graph).not_to have_received(:get_object)
    integration.update!(token_expires_at: 1.day.from_now)
    allow(graph).to receive(:get_object) do
      integration.update!(ad_account_id: "555555")
      ad
    end
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(message.reload.context).not_to have_key("ad_attribution")
  end

  it "preserva a mensagem recebida quando a API falha e agenda retry" do
    message = receive_event
    clear_enqueued_jobs
    allow(graph).to receive(:get_object).and_raise(Koala::Facebook::APIError.new(503, nil, { "code" => 2, "message" => "Temporary" }))
    expect { described_class.perform_now(tenant.id, message.lead_id, message.id) }.to have_enqueued_job(described_class)
    expect(message.reload.body).to eq("Tenho interesse")
    expect(message.context).not_to have_key("ad_attribution")
  end

  it "mantém o recebimento quando a fila de enriquecimento está indisponível" do
    allow(described_class).to receive(:perform_later).and_raise(StandardError, "Falha da fila")
    message = receive_event
    expect(message.body).to eq("Tenho interesse")
    expect(message.lead.other_information.dig("instagram_entry", "message_id")).to eq("paid-1")
  end

  it "aceita a referência de anúncio no nível do evento" do
    event["referral"] = event["message"].delete("referral")
    message = receive_event
    described_class.perform_now(tenant.id, message.lead_id, message.id)
    expect(message.reload.context.dig("ad_attribution", "meta_ad_name")).to eq("Anúncio A")
  end
end
