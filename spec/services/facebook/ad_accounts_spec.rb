require "rails_helper"

RSpec.describe Facebook::MetaService do
  it "consulta todas as páginas de contas acessíveis e remove duplicatas" do
    graph = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).with("token").and_return(graph)
    first = [{"account_id" => "123456", "name" => "Primeira"}]
    second = [first.first, {"account_id" => "789012", "name" => "Segunda"}]
    first.define_singleton_method(:next_page) { second }
    expect(graph).to receive(:get_connections).with("me", "adaccounts", fields: "account_id,name").and_return(first)
    expect(described_class.new("token").ad_accounts(all: true).map { |account| account["name"] }).to eq(["Primeira", "Segunda"])
  end
  it "consulta apenas negócios das páginas autorizadas" do
    graph = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).and_return(graph)
    expect(graph).to receive(:get_connections).with("me", "accounts", fields: "id,business").and_return([{"business" => {"id" => "salute"}}])
    expect(graph).to receive(:get_connections).with("salute", "owned_ad_accounts", fields: "account_id,name").and_return([{"account_id" => "123"}])
    expect(graph).to receive(:get_connections).with("salute", "client_ad_accounts", fields: "account_id,name").and_return([])
    expect(described_class.new("token").ad_accounts).to eq([{"account_id" => "123"}])
  end

  it "não consulta negócios de outras páginas autorizadas no mesmo login" do
    graph = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).and_return(graph)
    expect(graph).to receive(:get_connections).with("me", "accounts", fields: "id,business").and_return([
      {"id" => "1", "business" => {"id" => "salute"}}, {"id" => "2", "business" => {"id" => "conexao"}}
    ])
    expect(graph).to receive(:get_connections).with("salute", "owned_ad_accounts", fields: "account_id,name").and_return([{"account_id" => "123"}])
    expect(graph).to receive(:get_connections).with("salute", "client_ad_accounts", fields: "account_id,name").and_return([])
    expect(described_class.new("token").ad_accounts(page_ids: ["1"])).to eq([{"account_id" => "123"}])
  end

end
