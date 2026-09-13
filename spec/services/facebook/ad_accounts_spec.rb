require "rails_helper"

RSpec.describe Facebook::MetaService do
  it "consulta todas as páginas de contas acessíveis e remove duplicatas" do
    graph = instance_double(Koala::Facebook::API)
    allow(Koala::Facebook::API).to receive(:new).with("token").and_return(graph)
    first = [{"account_id" => "123456", "name" => "Primeira"}]
    second = [first.first, {"account_id" => "789012", "name" => "Segunda"}]
    first.define_singleton_method(:next_page) { second }
    expect(graph).to receive(:get_connections).with("me", "adaccounts", fields: "account_id,name").and_return(first)
    expect(described_class.new("token").ad_accounts.map { |account| account["name"] }).to eq(["Primeira", "Segunda"])
  end
end
