require "rails_helper"
RSpec.describe Instagram::Connection do
  let(:integration) { create(:user_meta_integration) }
  let(:page) { create(:meta_facebook_page, user_meta_integration: integration) }
  before do
    integration.update!(selected_page_ids: [page.page_id])
    allow(described_class).to receive(:verify_app_subscription!)
  end

  it "descobre sem ativar automaticamente" do
    graph = double("Graph")
    allow(Koala::Facebook::API).to receive(:new).and_return(graph)
    allow(graph).to receive(:get_object).with(page.page_id, fields: "instagram_business_account{id,username}").and_return({"instagram_business_account" => {"id" => "12345", "username" => "empresa"}})
    described_class.discover(page)
    expect(page.reload.instagram_id).to eq("12345")
    expect(page.instagram_enabled).to be(false)
  end
  it "confirma a inscrição antes de concluir a ativação" do
    page.update!(instagram_id: "12345")
    allow(described_class).to receive(:discover)
    allow(Meta::WebhookConfiguration).to receive(:gateway?).and_return(false)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FACEBOOK_APP_ID").and_return("app")
    service = double("Meta", subscribe_page_to_app: true)
    allow(Facebook::MetaService).to receive(:new).and_return(service)
    graph = double("Graph", get_connections: [{"id" => "app", "subscribed_fields" => ["messages", "leadgen"]}])
    allow(Koala::Facebook::API).to receive(:new).and_return(graph)
    described_class.activate(page)
    expect(page.reload.instagram_enabled).to be(true)
    expect(page.instagram_checked_at).to be_present
    expect(page.instagram_sync_error).to be_nil
  end
  it "ativa somente após inscrição e reverte a ativação se a Meta falhar" do
    page.update!(instagram_id: "12345")
    allow(Meta::WebhookConfiguration).to receive(:gateway?).and_return(false)
    allow(described_class).to receive(:discover)
    service = double("Meta")
    allow(Facebook::MetaService).to receive(:new).and_return(service)
    allow(service).to receive(:subscribe_page_to_app).and_raise(Facebook::MetaService::MetaAPIError)
    expect { described_class.activate(page) }.to raise_error(Facebook::MetaService::MetaAPIError)
    expect(page.reload.instagram_enabled).to be(false)
    expect(page.instagram_sync_error).to be_present
  end
  it "recusa um aplicativo sem inscrição Instagram no destino esperado" do
    allow(described_class).to receive(:verify_app_subscription!).and_call_original
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FACEBOOK_APP_ID").and_return("app")
    allow(ENV).to receive(:[]).with("FACEBOOK_APP_SECRET").and_return("secret")
    allow(Meta::WebhookConfiguration).to receive(:callback_url).and_return("https://gateway.test/webhooks/meta")
    graph = double("App", get_connections: [{"object" => "instagram", "active" => true, "callback_url" => "https://other.test", "fields" => [{"name" => "messages"}]}])
    allow(Koala::Facebook::API).to receive(:new).with("app|secret").and_return(graph)
    expect { described_class.verify_app_subscription! }.to raise_error(Instagram::Connection::Error, /configuração do sistema/)
    allow(graph).to receive(:get_connections).and_return([{"object" => "instagram", "active" => true, "callback_url" => "https://gateway.test/webhooks/meta", "fields" => [{"name" => "messages"}]}])
    expect { described_class.verify_app_subscription! }.not_to raise_error
  end
end
