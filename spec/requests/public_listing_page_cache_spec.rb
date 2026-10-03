require "rails_helper"

RSpec.describe "Cache de listagens canônicas", type: :request do
  let(:tenant) { Tenant.default }
  before do
    host! "localhost"
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    Setting.set(PublicPageCache::MODE_SETTING_KEY, "on", tenant: tenant)
    create(:habitation, tenant: tenant, codigo: "CACHE-VENDA", status: "Venda", valor_venda_cents: 50_000_000, valor_locacao_cents: 0)
    create(:habitation, tenant: tenant, codigo: "CACHE-ALUGUEL", status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 300_000)
    get "/imoveis"
  end

  def warm(path)
    3.times { get path }
    expect(response.headers["X-Public-Page-Cache"]).to eq("hit")
  end

  def codes
    Nokogiri::HTML(response.body).css("[data-property-code]").map { |node| node["data-property-code"] }
  end

  it "separa os caminhos filtrados e renova após alterar um imóvel" do
    warm("/imoveis/venda")
    expect(codes).to include("CACHE-VENDA")
    expect(codes).not_to include("CACHE-ALUGUEL")
    warm("/imoveis/aluguel")
    expect(codes).to include("CACHE-ALUGUEL")
    expect(codes).not_to include("CACHE-VENDA")

    tenant.habitations.find_by!(codigo: "CACHE-VENDA").update!(valor_venda_cents: 60_000_000)
    get "/imoveis/venda"
    expect(response.headers["X-Public-Page-Cache"]).to eq("miss")
  end

  it "não compartilha query de filtro nem resposta do Turbo com a página inteira" do
    warm("/imoveis/venda")
    get "/imoveis", params: { transaction_type: "locacao" }
    expect(response.headers["X-Public-Page-Cache"]).to be_nil
    expect(codes).not_to include("CACHE-VENDA")
    get "/imoveis/venda", params: { utm_campaign: "campanha-atual" }
    expect(response.headers["X-Public-Page-Cache"]).to be_nil
    get "/imoveis/venda", headers: { "Turbo-Frame" => "public-listing-grid" }
    expect(response.headers["X-Public-Page-Cache"]).to be_nil
    expect(response.body).not_to include("<!DOCTYPE")
    expect(codes).to include("CACHE-VENDA")
  end
end
