require "rails_helper"

RSpec.describe Linkedin::CatalogSync do
  it "carrega apenas contas selecionadas e compartilha formulários entre campanhas sem duplicar" do
    integration = create(:linkedin_integration)
    client = instance_double(Linkedin::Client)
    allow(client).to receive(:accounts).and_return([{ "id" => 123, "name" => "Conta" }, { "id" => 999, "name" => "Não selecionada" }])
    allow(client).to receive(:forms).with("123").and_return([{ "id" => 789, "name" => "Form" }])
    allow(client).to receive(:campaigns).with("123").and_return([{ "id" => 456, "name" => "A" }, { "id" => 457, "name" => "B" }])
    creatives = [456, 456, 457].map { |id| { "campaign" => "urn:li:sponsoredCampaign:#{id}", "leadgenCallToAction" => { "destination" => "urn:li:adForm:789" } } }
    allow(client).to receive(:creatives).with("123").and_return(creatives)
    described_class.call(integration, client: client)
    expect(integration.reload.campaign_structure.keys).to contain_exactly("456", "457")
    expect(integration.form_ids_for(["456", "457"])).to eq(["789"])
    expect(integration.catalog["456"]["forms"].size).to eq(1)
    expect(client).not_to have_received(:forms).with("999")
  end

  it "expõe falhas parciais sem perder os recursos de contas acessíveis" do
    integration = create(:linkedin_integration, selected_account_ids: ["123", "124"])
    client = instance_double(Linkedin::Client)
    allow(client).to receive(:accounts).and_return([{ "id" => 123, "name" => "Falha" }, { "id" => 124, "name" => "Acessível" }])
    allow(client).to receive(:forms).with("123").and_raise(Linkedin::Client::Error, "Permissão recusada.")
    allow(client).to receive(:forms).with("124").and_return([{ "id" => 790, "name" => "Form" }])
    allow(client).to receive(:campaigns).with("124").and_return([{ "id" => 457, "name" => "Campanha" }])
    allow(client).to receive(:creatives).with("124").and_return([{ "campaign" => "urn:li:sponsoredCampaign:457", "leadgenCallToAction" => { "destination" => "urn:li:adForm:790" } }])
    expect(described_class.call(integration, client: client)).to eq(["Permissão recusada."])
    expect(integration.reload.catalog.keys).to eq(["457"])
    expect(integration.catalog_synced_at).to be_nil
  end

end
