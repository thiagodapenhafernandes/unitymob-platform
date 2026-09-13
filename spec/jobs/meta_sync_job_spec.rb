require "rails_helper"

RSpec.describe MetaSyncJob, type: :job do
  let(:integration) { create(:user_meta_integration) }
  let(:service) { instance_double(Facebook::MetaService) }
  let(:job) { described_class.new }

  before do
    allow(job).to receive(:sleep)
    allow(job).to receive(:broadcast_status)
    allow(job).to receive(:register_meta_gateway_route).and_return(true)
    allow(Facebook::MetaService).to receive(:new).and_return(service)
    allow(service).to receive(:get_user_pages).and_return([
      {"id" => "11111", "name" => "Primeira", "access_token" => "token-page"},
      {"id" => "22222", "name" => "Segunda", "access_token" => "token-page"}
    ])
    allow(Instagram::Connection).to receive(:discover)
    allow(service).to receive(:get_page_lead_forms).and_return([])
    allow(service).to receive(:subscribe_page_to_app)
  end

  it "continua formulários e inscrições após falha de rede no Instagram e mantém pendências" do
    allow(Instagram::Connection).to receive(:discover).and_raise(Timeout::Error, "token-secreto")
    expect(ResetSyncStatusJob).not_to receive(:set)
    job.perform(integration.id)
    expect(service).to have_received(:get_page_lead_forms).twice
    expect(service).to have_received(:subscribe_page_to_app).twice
    expect(integration.reload.sync_status).to eq("partial")
    expect(integration.sync_message).to include("Instagram", "Primeira", "Segunda")
    expect(integration.sync_message).not_to include("token-secreto")
    expect(integration.last_sync_error).to include("Falha de comunicação")
  end

  it "inscreve webhooks mesmo se formulários falham e continua a página seguinte" do
    allow(service).to receive(:get_page_lead_forms).with("11111", "token-page").and_raise(StandardError, "segredo")
    job.perform(integration.id)
    expect(service).to have_received(:subscribe_page_to_app).with("11111", "token-page")
    expect(service).to have_received(:get_page_lead_forms).with("22222", "token-page")
    expect(integration.reload.sync_status).to eq("partial")
    expect(integration.sync_message).to include("Formulários da página Primeira")
  end

  it "só indica sucesso completo quando todas as etapas passam" do
    integration.update!(last_sync_error: "Falha anterior")
    job.perform(integration.id)
    expect(integration.reload.last_sync_error).to be_nil
    expect(integration.sync_status).to eq("completed")
    expect(ResetSyncStatusJob).to have_been_enqueued.with(integration.id, integration.updated_at.iso8601(6))
  end

  it "persiste motivo de falha fatal para consulta posterior" do
    allow(service).to receive(:get_user_pages).and_raise(Timeout::Error, "token-secreto")
    expect { job.perform(integration.id) }.to raise_error(Timeout::Error)
    expect(integration.reload.sync_status).to eq("failed")
    expect(integration.last_sync_error).to include("Buscando suas páginas", "Falha de comunicação")
    expect(integration.last_sync_error).not_to include("token-secreto")
  end

  it "não apaga pendências ou outra execução com o reset de uma execução anterior" do
    integration.update!(sync_status: "partial", sync_message: "Pendente")
    ResetSyncStatusJob.perform_now(integration.id)
    expect(integration.reload.sync_status).to eq("partial")
    integration.update!(sync_status: "completed")
    ResetSyncStatusJob.perform_now(integration.id, 1.day.ago.iso8601(6))
    expect(integration.reload.sync_status).to eq("completed")
  end
end
