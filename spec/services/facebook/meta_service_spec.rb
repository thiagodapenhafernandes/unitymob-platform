require "rails_helper"

RSpec.describe Facebook::MetaService do
  describe "#get_user_pages" do
    it "includes pages connected through business assets" do
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

      expect(pages.map { |page| page["id"] }).to contain_exactly("page-1", "page-2", "page-3")
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

      expect(pages.map { |page| page["id"] }).to contain_exactly("page-1", "page-2")
      expect(pages.count { |page| page["id"] == "page-1" }).to eq(1)
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
