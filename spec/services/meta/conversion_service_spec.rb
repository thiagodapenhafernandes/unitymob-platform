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
      expect(event["custom_data"]).to eq("event_source" => "crm", "lead_event_source" => "Unitymob")
      expect(event["user_data"]).not_to have_key("lead_id")
    end
  end

  it "inclui valor em BRL no Purchase e código de teste quando configurado" do
    config.update!(test_event_code: "TEST123")

    described_class.new(config).send_event(
      lead: lead, event_name: "Purchase", event_id: "evt-2", occurred_at: Time.current, value: 850000.0
    )

    expect(graph).to have_received(:graph_call).with("999/events", kind_of(Hash), "post") do |_, payload, _|
      event = payload["data"].first
      expect(event["custom_data"]).to eq({ "event_source" => "crm", "lead_event_source" => "Unitymob", "value" => 850000.0, "currency" => "BRL" })
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

  [
    { "meta_leadgen_id" => "1234567890123456" },
    { "facebook_attributes" => { "leadgen_id" => "1234567890123456" } },
    { "external_lead_payload" => { "facebook_attributes" => { "leadgen_id" => "1234567890123456" } } },
    { "data" => { "facebook_attributes" => { "leadgen_id" => "1234567890123456" } } }
  ].each do |information|
    it "envia o identificador original da Meta em #{information.keys.first}, mesmo sem contato" do
      lead.update_columns(other_information: information, email: nil, phone: nil, client_email: nil, client_phone: nil)

      expect(described_class.new(config).send_event(
        lead: lead, event_name: "QualifiedLead", event_id: "evt-meta", occurred_at: Time.current
      )).to eq(:sent)

      expect(graph).to have_received(:graph_call).with("999/events", kind_of(Hash), "post") do |_, payload, _|
        expect(payload["data"].first["user_data"]["lead_id"]).to eq("1234567890123456")
      end
    end
  end

  it "usa a atribuição Meta como fallback sem confundir o ID interno do CRM" do
    lead.update_columns(attribution_data: { "facebook" => { "leadgen_id" => "1234567890123456" } })
    described_class.new(config).send_event(lead: lead, event_name: "Schedule", event_id: "evt-meta", occurred_at: Time.current)

    expect(graph).to have_received(:graph_call).with("999/events", kind_of(Hash), "post") do |_, payload, _|
      expect(payload["data"].first["user_data"]["lead_id"]).to eq("1234567890123456")
    end
  end

  it "embrulha erro da Meta sem vazar payload" do
    allow(graph).to receive(:graph_call).and_raise(Koala::Facebook::APIError.new(400, nil, { "code" => 100, "message" => "bad" }))

    expect do
      described_class.new(config).send_event(
        lead: lead, event_name: "Schedule", event_id: "evt-4", occurred_at: Time.current
      )
    end.to raise_error(Meta::ConversionService::ConversionError, /CAPI Schedule lead_id=#{lead.id} dataset=999/)
  end

  [nil, {}, [], { "events_received" => 0 }, { "events_received" => -1 },
   { "events_received" => 2 }, { "events_received" => "1" }].each do |response|
    it "rejeita resposta sem confirmação unitária: #{response.inspect}" do
      allow(graph).to receive(:graph_call).and_return(response)

      expect do
        described_class.new(config).send_event(lead: lead, event_name: "Schedule", event_id: "evt-ack", occurred_at: Time.current)
      end.to raise_error(Meta::ConversionService::ConversionError, /recebimento não confirmado/)
      expect(graph).not_to have_received(:graph_call).with("888/events", anything, anything)
    end
  end

  it "só confirma sucesso após todos os datasets e preserva o evento no retry" do
    allow(graph).to receive(:graph_call).with("888/events", anything, "post")
      .and_return({ "events_received" => 0 }, { "events_received" => 1 })
    service = described_class.new(config)
    occurred_at = Time.current
    args = { lead: lead, event_name: "Schedule", event_id: "evt-retry", occurred_at: occurred_at }

    expect { service.send_event(**args) }.to raise_error(Meta::ConversionService::ConversionError, /dataset=888/)
    expect(service.send_event(**args)).to eq(:sent)
    %w[999 888].each do |id|
      expect(graph).to have_received(:graph_call).with("#{id}/events", anything, "post").twice do |_, payload, _|
        expect(payload['data'].first).to include('event_id' => 'evt-retry', 'event_time' => occurred_at.to_i)
      end
    end
  end

  it "não expõe a resposta não confirmada no erro ou no log" do
    allow(graph).to receive(:graph_call).and_return({ "events_received" => 0, "message" => "segredo-do-provedor" })
    allow(Rails.logger).to receive(:info)

    expect do
      described_class.new(config).send_event(lead: lead, event_name: "Schedule", event_id: "evt-safe", occurred_at: Time.current)
    end.to raise_error(Meta::ConversionService::ConversionError) { |error| expect(error.message).not_to include('segredo-do-provedor') }
    expect(Rails.logger).not_to have_received(:info).with(a_string_including('[Meta::ConversionService]'))
    expect(Rails.logger).not_to have_received(:info).with(a_string_including('segredo-do-provedor'))
  end

  it "bloqueia chamada direta quando o token expira antes do envio" do
    UserMetaIntegration.owned_by_tenant(tenant.id).update_all(token_expires_at: 1.second.ago)

    expect do
      described_class.new(config).send_event(lead: lead, event_name: "Schedule", event_id: "evt-expired", occurred_at: Time.current)
    end.to raise_error(Meta::ConversionService::ConversionError, /sem token Meta válido/)
    expect(graph).not_to have_received(:graph_call)
  end

  it "usa somente os datasets, token e modo de teste configurados em cada conta" do
    other_tenant = Tenant.create!(name: "Outra conta", slug: "outra-capi-#{SecureRandom.hex(3)}")
    other_admin = create(:admin_user, tenant: other_tenant)
    create(:user_meta_integration, admin_user: other_admin, tenant: other_tenant, access_token: "other-token")
    other_config = MetaConversionConfig.create!(tenant: other_tenant, datasets: [{ "id" => "777" }], test_event_code: "OTHER_TEST")
    other_lead = create(:lead, tenant: other_tenant, email: "outro@example.com", attribution_channel: "meta_ads")
    other_graph = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).with("other-token").and_return(other_graph)
    allow(other_graph).to receive(:graph_call).and_return({ "events_received" => 1 })

    expect(described_class.new(config).send_event(lead: lead, event_name: "Contact", event_id: "first", occurred_at: Time.current)).to eq(:sent)
    expect(described_class.new(other_config).send_event(lead: other_lead, event_name: "Schedule", event_id: "second", occurred_at: Time.current)).to eq(:sent)

    expect(graph).to have_received(:graph_call).with("999/events", anything, "post")
    expect(graph).to have_received(:graph_call).with("888/events", anything, "post")
    expect(graph).not_to have_received(:graph_call).with("777/events", anything, "post")
    expect(other_graph).to have_received(:graph_call).with("777/events", hash_including("test_event_code" => "OTHER_TEST"), "post").once
    expect(other_graph).not_to have_received(:graph_call).with("999/events", anything, "post")
    expect(other_graph).not_to have_received(:graph_call).with("888/events", anything, "post")
  end
end
