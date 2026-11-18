require "rails_helper"

RSpec.describe "Correlação da entrega Meta" do
  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:lead) { create(:lead, tenant: tenant, attribution_channel: "meta_ads", email: "private@example.test", skip_automatic_routing: true) }
  let(:config) { MetaConversionConfig.create!(tenant: tenant, datasets: [{ "id" => "999" }, { "id" => "888" }]) }
  let(:graph) { instance_double(Koala::Facebook::API) }
  let(:context) { Tracking::Correlation.change(lead) }
  let(:args) { { lead: lead, event_name: "QualifiedLead", event_id: Meta::ConversionDispatcher.event_id(tenant.id, lead.id, "QualifiedLead"), occurred_at: Time.current, correlation: context } }

  before do
    create(:user_meta_integration, tenant: tenant, admin_user: owner, access_token: "secret-token")
    allow(Koala::Facebook::API).to receive(:new).with("secret-token").and_return(graph)
    allow(graph).to receive(:graph_call).and_return({ "events_received" => 1, "fbtrace_id" => "trace-ok" })
  end

  it "registra cada dataset, conserva IDs no retry e não confunde recebimento com atribuição" do
    allow(graph).to receive(:graph_call).with("888/events", anything, "post")
      .and_return({ "events_received" => 0, "message" => "private-response" }, { "events_received" => 1, "fbtrace_id" => "trace-second" })
    service = Meta::ConversionService.new(config)
    expect { service.send_event(**args) }.to raise_error(Meta::ConversionService::ConversionError)
    links = lead.tracking_event_links.where(transport: "meta").index_by(&:destination_label)
    expect(links.fetch("999").delivery_status).to eq("received")
    expect(links.fetch("888").delivery_status).to eq("uncertain")
    expect(service.send_event(**args)).to eq(:sent)
    links.each_value do |link|
      expect(link.reload.delivery_status).to eq("received")
      expect(link.delivery_attempts.size).to eq(2)
      expect(link.external_event_id).to eq(args[:event_id])
      expect(link.attributes.to_json).not_to include("private-response", "private@example.test", "secret-token")
    end
    expect(graph).to have_received(:graph_call).with("999/events", anything, "post").twice do |_, payload, _|
      sent = JSON.parse(payload.fetch("data")).sole
      expect(sent["event_id"]).to eq(args[:event_id])
      expect(sent).not_to have_key("correlation_id")
    end
  end

  it "mantém jobs antigos executáveis sem inventar uma correlação retroativa" do
    config
    MetaConversionJob.perform_now(tenant.id, lead.id, "QualifiedLead", "legacy-event", Time.current.iso8601, nil)
    expect(graph).to have_received(:graph_call).with("999/events", anything, "post")
    expect(lead.tracking_event_links).to be_empty
  end

  it "transporta a correlação pela serialização real do ActiveJob" do
    config
    job = MetaConversionJob.new(tenant.id, lead.id, "QualifiedLead", args[:event_id], Time.current.iso8601, nil, context)
    MetaConversionJob.execute(job.serialize)
    expect(lead.tracking_event_links.count).to eq(2)
    expect(lead.tracking_event_links.map(&:delivery_status)).to eq(%w[received received])
    expect(lead.tracking_event_links.pluck(:occurrence_key).uniq).to eq([context[:occurrence_key]])
  end

  it "identifica a ocorrência de cada reenvio sem reescrever a referência original do ID Meta" do
    service = Meta::ConversionService.new(config)
    original_context = context
    service.send_event(**args)
    lead.update!(notes: "Nova ação comercial")
    later_context = Tracking::Correlation.change(lead)
    service.send_event(**args.merge(correlation: later_context))
    expect(lead.tracking_event_links.count).to eq(2)
    lead.tracking_event_links.each do |link|
      expect(link.occurrence_key).to eq(original_context[:occurrence_key])
      expect(link.delivery_attempts.map { |attempt| attempt["occurrence_key"] })
        .to eq([original_context[:occurrence_key], later_context[:occurrence_key]])
    end
  end

  it "registra configuração desativada após enfileiramento sem chamar a Meta" do
    config
    Meta::ConversionDispatcher.call(lead: lead, event_name: "QualifiedLead", correlation: context)
    config.update!(enabled: false)
    MetaConversionJob.perform_now(tenant.id, lead.id, "QualifiedLead", args[:event_id], Time.current.iso8601, nil, context)
    expect(graph).not_to have_received(:graph_call)
    expect(lead.tracking_event_links.map(&:delivery_status)).to eq(%w[skipped skipped])
    expect(lead.tracking_event_links.map(&:delivery_skip_reason)).to eq(%w[config_inactive config_inactive])
  end

  it "continua enviando se o registro de correlação estiver indisponível" do
    allow(TrackingEventLink).to receive(:create_or_find_by!).and_raise(ActiveRecord::StatementInvalid, "private-error")
    expect(Meta::ConversionService.new(config).send_event(**args)).to eq(:sent)
    expect(graph).to have_received(:graph_call).with("999/events", anything, "post")
    expect(graph).to have_received(:graph_call).with("888/events", anything, "post")
  end
end
