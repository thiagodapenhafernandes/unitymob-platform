require "rails_helper"
RSpec.describe Facebook::MetaService do
  it "preserva leadgen e outras inscrições ao adicionar mensagens" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FACEBOOK_APP_ID").and_return("app")
    graph = double("Graph")
    allow(Koala::Facebook::API).to receive(:new).and_return(graph)
    allow(graph).to receive(:get_connections).with("page", "subscribed_apps", fields: "id,subscribed_fields").and_return([{"id" => "app", "subscribed_fields" => ["leadgen", "feed"]}])
    expect(graph).to receive(:put_connections).with("page", "subscribed_apps", subscribed_fields: "leadgen,feed,messages").and_return({"success" => true})
    described_class.new("token").subscribe_page_to_app("page", "token", subscribed_fields: ["messages"])
  end
end
