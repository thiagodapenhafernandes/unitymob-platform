require "tmpdir"

RSpec.shared_context "isolated sitemap snapshots" do
  around do |example|
    Dir.mktmpdir("sitemap-snapshots") do |directory|
      @sitemap_snapshot_directory = directory
      example.run
    end
  end

  before do
    allow(Seo::SitemapCache).to receive(:store).and_return(ActiveSupport::Cache::FileStore.new(@sitemap_snapshot_directory))
  end
end
