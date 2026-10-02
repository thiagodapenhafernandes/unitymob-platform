require "rails_helper"

RSpec.describe "Admin > Desempenho (cache do site)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    allow(Rails).to receive(:cache).and_return(store)
    sign_in admin
  end

  def mode = PublicPageCache.mode(tenant)

  it "mostra a tela com o cache desativado por padrão" do
    get admin_site_cache_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Desempenho").and include("Desativado")
    expect(mode).to eq("off")
  end

  it "liga o teste, o modo ativo e desliga de novo, só para a conta atual" do
    patch admin_site_cache_path, params: { mode: "shadow" }
    expect(response).to redirect_to(admin_site_cache_path)
    expect(mode).to eq("shadow")

    patch admin_site_cache_path, params: { mode: "on" }
    expect(mode).to eq("on")

    patch admin_site_cache_path, params: { mode: "off" }
    expect(mode).to eq("off")
  end

  it "rejeita modo inválido" do
    patch admin_site_cache_path, params: { mode: "turbo" }
    expect(mode).to eq("off")
    expect(flash[:alert]).to be_present
  end

  it "mostra a orientação conforme o resultado do teste" do
    patch admin_site_cache_path, params: { mode: "shadow" }
    30.times { PublicSite::PageCacheStats.record(tenant.id, :equal) }
    get admin_site_cache_path
    expect(response.body).to include("Pronto para ativar")

    PublicSite::PageCacheStats.record(tenant.id, :diverged, detail: "bytes=1->2")
    get admin_site_cache_path
    expect(response.body).to include("Não ative ainda").and include("bytes=1-&gt;2")
  end

  it "limpa o cache subindo a versão da conta" do
    before_version = PublicSite::PageVersion.current(tenant.id)
    post clear_admin_site_cache_path
    expect(PublicSite::PageVersion.current(tenant.id)).not_to eq(before_version)
  end

  it "vale por conta: ligar numa conta não liga na outra" do
    other = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}")

    patch admin_site_cache_path, params: { mode: "on" }

    expect(PublicPageCache.mode(tenant)).to eq("on")
    expect(PublicPageCache.mode(other)).to eq("off")
  end
end
