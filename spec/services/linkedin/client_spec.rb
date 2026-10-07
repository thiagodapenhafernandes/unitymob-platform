require "rails_helper"

RSpec.describe Linkedin::Client do
  let(:client) { described_class.new("private-token") }

  it "percorre todas as páginas de contas usando cursor" do
    expect(client).to receive(:get).with("adAccounts", hash_including(pageSize: 100)).ordered.and_return({ "elements" => [{ "id" => 123 }], "metadata" => { "nextPageToken" => "next" } })
    expect(client).to receive(:get).with("adAccounts", hash_including(pageToken: "next")).ordered.and_return({ "elements" => [{ "id" => 124 }], "metadata" => {} })
    expect(client.accounts.pluck("id")).to eq([123, 124])
  end

  it "usa o finder criteria para criativos" do
    expect(client).to receive(:get).with("adAccounts/123/creatives", hash_including(q: "criteria")).and_return({ "elements" => [] })
    expect(client.creatives("123")).to eq([])
  end

  it "pagina respostas sem buscar leads históricos fora do intervalo" do
    first = Array.new(100) { |id| { "id" => id } }
    expect(client).to receive(:get).with("leadFormResponses", hash_including(submittedAtTimeRange: "(start:1000,end:2000)", start: 0)).ordered.and_return({ "elements" => first, "paging" => { "total" => 101 } })
    expect(client).to receive(:get).with("leadFormResponses", hash_including(start: 100)).ordered.and_return({ "elements" => [{ "id" => 100 }], "paging" => { "total" => 101 } })
    expect(client.responses("123", from: 1000, to: 2000).size).to eq(101)
  end

  it "não expõe corpo, token ou URL nos erros da API" do
    response = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
    allow(response).to receive(:body).and_return('private-token client-secret personal-data')
    allow(Net::HTTP).to receive(:start).and_return(response)
    expect { client.accounts }.to raise_error(Linkedin::Client::Error, /aprovação Lead Sync/) do |error|
      expect(error.message).not_to include("private-token", "client-secret", "personal-data")
    end
  end
end
