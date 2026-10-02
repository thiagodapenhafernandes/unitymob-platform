require "rails_helper"

RSpec.describe Facebook::MetaService do
  describe "#get_user_pages" do
    it "limits pages to the current authorization" do
      graph = fake_graph(
        ["me", "accounts"] => connection([
          page("page-1", "Página direta")
        ]),
        ["me", "businesses"] => connection([
          { "id" => "business-1", "name" => "Negócio" }
        ]),
        ["business-1", "owned_pages"] => connection([
          page("page-2", "Página própria do negócio")
        ]),
        ["business-1", "client_pages"] => connection([
          page("page-3", "Página cliente do negócio")
        ])
      )

      allow(Koala::Facebook::API).to receive(:new).with("token").and_return(graph)

      pages = described_class.new("token").get_user_pages

      expect(pages.map { |page| page["id"] }).to contain_exactly("page-1")
    end

    it "deduplicates pages returned by more than one Meta connection" do
      graph = fake_graph(
        ["me", "accounts"] => connection([
          page("page-1", "Página direta")
        ]),
        ["me", "businesses"] => connection([
          { "id" => "business-1", "name" => "Negócio" }
        ]),
        ["business-1", "owned_pages"] => connection([
          page("page-1", "Página direta duplicada")
        ]),
        ["business-1", "client_pages"] => connection([
          page("page-2", "Página cliente")
        ])
      )

      allow(Koala::Facebook::API).to receive(:new).with("token").and_return(graph)

      pages = described_class.new("token").get_user_pages

      expect(pages.map { |page| page["id"] }).to contain_exactly("page-1")
      expect(pages.count { |page| page["id"] == "page-1" }).to eq(1)
    end
  end

  describe "#ad_account_pixels" do
    it "lista datasets do ad account e tolera falha de API" do
      graph = fake_graph(
        ["act_123", "adspixels"] => connection([{ "id" => "pix-1", "name" => "Pixel Loja" }])
      )
      allow(Koala::Facebook::API).to receive(:new).with("token").and_return(graph)

      expect(described_class.new("token").ad_account_pixels("123")).to eq([{ "id" => "pix-1", "name" => "Pixel Loja" }])
    end

    it "retorna vazio quando a Meta recusa" do
      graph = instance_double(Koala::Facebook::API)
      allow(graph).to receive(:get_connections).and_raise(Koala::Facebook::APIError.new(400, nil, { "code" => 100 }))
      allow(Koala::Facebook::API).to receive(:new).with("token").and_return(graph)

      expect(described_class.new("token").ad_account_pixels("123")).to eq([])
    end
  end

  describe "#campaign_insights" do
    it "busca linhas diárias por campanha na janela" do
      rows = [{ "campaign_id" => "c1", "spend" => "10" }]
      graph = fake_graph(["act_123", "insights"] => connection(rows))
      allow(Koala::Facebook::API).to receive(:new).with("token").and_return(graph)

      result = described_class.new("token").campaign_insights("123", start_date: Date.current - 7, end_date: Date.current)

      expect(result).to eq(rows)
    end
  end

  describe ".lead_count_from_actions" do
    it "soma só ações de lead" do
      actions = [{ "action_type" => "lead", "value" => "2" },
                 { "action_type" => "onsite_conversion.lead_grouped", "value" => "1" },
                 { "action_type" => "link_click", "value" => "9" }]

      expect(described_class.lead_count_from_actions(actions)).to eq(3)
      expect(described_class.lead_count_from_actions(nil)).to eq(0)
    end
  end

  def fake_graph(responses)
    instance_double(Koala::Facebook::API).tap do |graph|
      allow(graph).to receive(:get_connections) do |object, connection_name, **|
        responses.fetch([object, connection_name]) { connection([]) }
      end
    end
  end

  def page(id, name)
    {
      "id" => id,
      "name" => name,
      "access_token" => "token-#{id}",
      "category" => "Imobiliária"
    }
  end

  def connection(records, next_page: nil)
    MetaConnection.new(records, next_page)
  end

  class MetaConnection < Array
    def initialize(records, next_page)
      super(records)
      @next_page = next_page
    end

    def next_page
      @next_page
    end
  end
end
