require "rails_helper"

RSpec.describe LinkedinSyncJob do
  let(:integration) { create(:linkedin_integration) }
  let(:client) { instance_double(Linkedin::Client) }
  before { allow(Linkedin::Client).to receive(:new).with(integration.access_token).and_return(client) }

  it "busca desde a ativação e avança o cursor apenas depois de processar" do
    since = integration.account_cursors["123"]["since"]
    row = { "id" => "a", "submittedAt" => since + 1000 }
    expect(client).to receive(:responses).with("123", from: since, to: kind_of(Integer)).and_return([row])
    expect(Linkedin::ReceiveLead).to receive(:call).with(integration, row, client: client)
    described_class.perform_now(integration.id)
    expect(integration.reload.last_synced_at).to be_present
    expect(integration.account_cursors["123"]["last"]).to be > since
  end

  it "não consome o cursor quando a API falha e exibe erro seguro" do
    cursors = integration.account_cursors
    allow(client).to receive(:responses).and_raise(Linkedin::Client::Error, "Falha de comunicação com o LinkedIn.")
    described_class.perform_now(integration.id)
    expect(integration.reload.account_cursors).to eq(cursors)
    expect(integration.last_synced_at).to be_nil
    expect(integration.last_error).to include("Falha de comunicação")
  end

  it "a falha de uma conta não impede a consulta da outra nem consome seu cursor" do
    original = integration.account_cursors["123"].deep_dup
    integration.update!(selected_account_ids: ["123", "124"], ad_accounts: integration.ad_accounts + [{ "id" => "124", "name" => "Outra conta" }],
      account_cursors: integration.account_cursors.merge("124" => original.deep_dup))
    allow(client).to receive(:responses).with("123", any_args).and_raise(Linkedin::Client::Error, "Acesso recusado.")
    expect(client).to receive(:responses).with("124", any_args).and_return([])
    described_class.perform_now(integration.id)
    expect(integration.reload.account_cursors["123"]).to eq(original)
    expect(integration.account_cursors["124"]["last"]).to be > original["since"]
    expect(integration.last_error).to include("Acesso recusado")
  end

  it "não consulta uma conexão expirada" do
    integration.update!(token_expires_at: 1.minute.ago)
    expect(client).not_to receive(:responses)
    described_class.perform_now(integration.id)
  end

  it "sinaliza conta revogada sem avançar seu cursor" do
    integration.update!(ad_accounts: [])
    before_cursor = integration.account_cursors
    expect(client).not_to receive(:responses)
    described_class.perform_now(integration.id)
    expect(integration.reload.account_cursors).to eq(before_cursor)
    expect(integration.last_error).to include("não está mais acessível")
  end

  it "mantém o tenant no contexto de recebimento e restaura o contexto ao terminar" do
    previous = Current.tenant
    row = { "id" => "context", "submittedAt" => integration.account_cursors["123"]["since"] + 1 }
    allow(client).to receive(:responses).and_return([row])
    expect(Linkedin::ReceiveLead).to receive(:call) { expect(Current.tenant).to eq(integration.tenant) }
    described_class.perform_now(integration.id)
    expect(Current.tenant).to eq(previous)
  end

  it "ignora histórico anterior à ativação mesmo se a API o retornar" do
    row = { "id" => "old", "submittedAt" => integration.account_cursors["123"]["since"] - 1 }
    allow(client).to receive(:responses).and_return([row])
    expect(Linkedin::ReceiveLead).not_to receive(:call)
    described_class.perform_now(integration.id)
  end
end
