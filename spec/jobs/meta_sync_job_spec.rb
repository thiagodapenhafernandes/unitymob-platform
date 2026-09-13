require "rails_helper"

RSpec.describe MetaSyncJob, type: :job do
  let(:integration) { create(:user_meta_integration, selected_page_ids: %w[11111 22222]) }
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

  it "envia o catálogo somente ao canal de suporte e omite nomes externos no progresso" do
    integration.update!(selected_page_ids: ["11111"])
    messages = []
    allow(job).to receive(:broadcast_status) { |record| messages << record.sync_message }
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    job.perform(integration.id)
    expect(messages.join(" ")).not_to include("Segunda")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "meta_selection_#{integration.id}", target: "meta_page_selection",
      partial: "admin/meta_integrations/page_selection", locals: {integration: integration})
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
      "meta_sync_#{integration.id}", hash_including(target: "meta_page_selection"))
  end

  it "descobre outras páginas sem ativar nem sincronizar seus formulários" do
    integration.update!(selected_page_ids: ["11111"])
    job.perform(integration.id)
    expect(integration.meta_facebook_pages.find_by!(page_id: "22222")).not_to be_active
    expect(service).not_to have_received(:get_page_lead_forms).with("22222", anything)
    expect(service).not_to have_received(:subscribe_page_to_app).with("22222", anything)
    expect(integration.reload.selected_page_ids).to eq(["11111"])
  end

  it "prepara o Direct automaticamente apenas na página selecionada" do
    integration.update!(selected_page_ids: ["11111"])
    allow(Instagram::Connection).to receive(:discover) { |page| page.update!(instagram_id: "ig-selected") }
    expect(Instagram::Connection).to receive(:activate) { |page| expect(page.page_id).to eq("11111") }
    job.perform(integration.id)
  end

  it "não ativa páginas de uma conexão sem seleção" do
    integration.update!(selected_page_ids: [])
    job.perform(integration.id)
    expect(integration.meta_facebook_pages.enabled).to be_empty
    expect(integration.reload.sync_status).to eq("partial")
    expect(integration.last_sync_error).to include("Nenhuma página foi vinculada", "salvar a seleção")
    expect(ResetSyncStatusJob).not_to have_been_enqueued.with(integration.id, anything)
    expect(service).not_to have_received(:get_page_lead_forms)
    expect(job).not_to have_received(:register_meta_gateway_route)
  end

  it "confirma o destino antes de ativar uma página nova" do
    allow(job).to receive(:register_meta_gateway_route) do |page, _integration|
      expect(MetaFacebookPage.find(page.id)).not_to be_active
      true
    end
    job.perform(integration.id)
    expect(integration.meta_facebook_pages.enabled.count).to eq(2)
  end

  it "desativa o recebimento se o gateway não confirmar o destino" do
    allow(job).to receive(:register_meta_gateway_route).and_return(false)
    job.perform(integration.id)
    expect(integration.meta_facebook_pages.enabled).to be_empty
    expect(service).not_to have_received(:get_page_lead_forms)
    expect(integration.reload.last_sync_error).to include("recebimento foi desativado")
  end

  it "preserva seleção quando a autorização deixa de retornar uma página" do
    integration.update!(selected_page_ids: ["33333"])
    job.perform(integration.id)
    expect(integration.reload.selected_page_ids).to eq(["33333"])
    expect(integration.last_sync_error).to include("33333", "preservada")
    expect(integration.meta_facebook_pages.enabled).to be_empty
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
