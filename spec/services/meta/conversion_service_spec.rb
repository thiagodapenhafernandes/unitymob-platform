require "rails_helper"

RSpec.describe Meta::ConversionService do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:config) { MetaConversionConfig.create!(tenant: tenant, datasets: [{ "id" => "999", "name" => "Loja" }, { "id" => "888" }]) }
  let(:lead) do
    create(:lead, tenant: tenant, name: "Maria Silva", email: "Maria@Exemplo.com.br",
                  phone: "+55 (47) 99999-0000", attribution_channel: "meta_ads")
  end
  let(:graph) { instance_double(Koala::Facebook::API) }

  before do
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "send-tok")
    allow(Koala::Facebook::API).to receive(:new).with("send-tok").and_return(graph)
    allow(graph).to receive(:graph_call).and_return({ "events_received" => 1, "fbtrace_id" => "abc" })
  end

  it "envia evento com user_data normalizado e hasheado, sem PII em claro" do
    result = described_class.new(config).send_event(
      lead: lead, event_name: "Schedule", event_id: "evt-1", occurred_at: Time.zone.local(2026, 10, 2, 12, 0)
    )

    expect(result).to eq(:sent)
    expect(graph).to have_received(:graph_call).with("999/events", kind_of(Hash), "post")
    expect(graph).to have_received(:graph_call).with("888/events", kind_of(Hash), "post")
    expect(graph).to have_received(:graph_call).with("999/events", kind_of(Hash), "post") do |_, payload, _|
      event = payload["data"].first
      expect(event["event_name"]).to eq("Schedule")
      expect(event["event_id"]).to eq("evt-1")
      expect(event["event_time"]).to eq(Time.zone.local(2026, 10, 2, 12, 0).to_i)
      expect(event["action_source"]).to eq("system_generated")
      expect(event["user_data"]["em"]).to eq(Digest::SHA256.hexdigest("maria@exemplo.com.br"))
      expect(event["user_data"]["ph"]).to eq(Digest::SHA256.hexdigest("5547999990000"))
      expect(event["user_data"]["fn"]).to eq(Digest::SHA256.hexdigest("maria"))
      expect(event["user_data"].values.join).not_to include("maria", "4799999")
      expect(event).not_to have_key("custom_data")
    end
  end

  it "inclui valor em BRL no Purchase e código de teste quando configurado" do
    config.update!(test_event_code: "TEST123")

    described_class.new(config).send_event(
      lead: lead, event_name: "Purchase", event_id: "evt-2", occurred_at: Time.current, value: 850000.0
    )

    expect(graph).to have_received(:graph_call).with("999/events", kind_of(Hash), "post") do |_, payload, _|
      event = payload["data"].first
      expect(event["custom_data"]).to eq({ "value" => 850000.0, "currency" => "BRL" })
      expect(payload["test_event_code"]).to eq("TEST123")
    end
  end

  it "descarta sem chamar a Meta quando não há e-mail nem telefone" do
    lead.update_columns(email: nil, phone: nil, client_email: nil, client_phone: nil)

    result = described_class.new(config).send_event(
      lead: lead, event_name: "Schedule", event_id: "evt-3", occurred_at: Time.current
    )

    expect(result).to eq(:skipped)
    expect(graph).not_to have_received(:graph_call)
  end

  it "embrulha erro da Meta sem vazar payload" do
    allow(graph).to receive(:graph_call).and_raise(Koala::Facebook::APIError.new(400, nil, { "code" => 100, "message" => "bad" }))

    expect do
      described_class.new(config).send_event(
        lead: lead, event_name: "Schedule", event_id: "evt-4", occurred_at: Time.current
      )
    end.to raise_error(Meta::ConversionService::ConversionError, /CAPI Schedule lead_id=#{lead.id} dataset=999/)
  end
end
