require "rails_helper"

RSpec.describe ExternalLeadMigration::Client do
  let(:client) { described_class.new(token: "test-token") }

  it "atualiza somente a fonte do mesmo cadastro via PUT" do
    expect(client).to receive(:request).with(Net::HTTP::Put, "/leads/other%2Fid",
      body: {data: {type: "lead", attributes: {"source" => "Disparo de WhatsApp", "type_negotiation" => "Alugar"}}})
    client.update_lead_routing("other/id", attributes: {"source" => "Disparo de WhatsApp", "type_negotiation" => "Alugar"})
  end

  it "reabre e redistribui o ID existente sem chamar a criação de leads" do
    expect(client).to receive(:post).with("/leads/remote-id/update_status", body: {status: 0, message: "Interesse confirmado"}).ordered
    expect(client).to receive(:post).with("/distribution_queues/remote-id/redistribute_lead", body: {id: "remote-id"}).ordered
    client.reactivate_lead("remote-id", message: "Interesse confirmado")
    client.redistribute_lead("remote-id")
  end

  it "escapa o ID externo como um único segmento da URL" do
    expect(client).to receive(:post).with("/distribution_queues/other%2Fid/redistribute_lead", body: {id: "other/id"})
    client.redistribute_lead("other/id")
  end

  it "envia o mesmo instante no relógio exigido pelo filtro C2S, sem mudar os parâmetros recebidos" do
    ["2026-11-12T12:58:14Z", "2026-11-12T09:58:14-03:00"].each do |stamp|
      params = { updated_gte: stamp, sort: "-updated_at" }
      expect(client).to receive(:get).with("/leads", params: hash_including(
        updated_gte: "2026-11-12T09:58:14Z", sort: "-updated_at", page: 1, perpage: 50
      )).and_return({})

      client.leads(page: 1, params: params)

      expect(params[:updated_gte]).to eq(stamp)
    end
  end

  it "mantém a data correta quando o filtro UTC atravessa a meia-noite brasileira" do
    expect(client).to receive(:get).with("/leads", params: hash_including(
      updated_gte: "2026-11-11T22:00:00Z"
    )).and_return({})

    client.leads(page: 1, params: { updated_gte: "2026-11-12T01:00:00Z" })
  end
end
