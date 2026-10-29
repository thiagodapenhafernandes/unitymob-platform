require "rails_helper"

RSpec.describe "Comissão real no fechamento", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  before do
    host! "localhost"
    sign_in admin
  end
  it "salva a comissão antes do fechamento e a registra na auditoria" do
    post close_deal_admin_lead_path(lead), params: { lead: { closing_commission: "1.250,50", tenant_id: 99999 } }
    expect(response).to redirect_to(admin_lead_path(lead))
    expect(lead.reload.closing_commission_cents).to eq(125050)
    expect(lead.tenant_id).to eq(admin.tenant_id)
    expect(lead.lead_audit_logs.order(:id).last.changeset).to have_key("closing_commission_cents")
  end
  it "vincula o fechamento à única etapa ganha do próprio funil" do
    stages = lead.lead_pipeline.closing_stages.to_a
    expect(stages.size).to eq(1)
    post close_deal_admin_lead_path(lead)
    expect(lead.reload.lead_pipeline_stage_id).to eq(stages.first.id)
    expect(lead.status).to eq(stages.first.name)
    expect(lead.closed_at).to be_present
  end

  it "exige escolha quando há mais de uma etapa ganha" do
    lead
    another = create(:lead_pipeline_stage, lead_pipeline: lead.lead_pipeline, name: "Contrato concluído", stage_type: "won")
    original = lead.attributes.slice("status", "lead_pipeline_stage_id", "closing_commission_cents")
    post close_deal_admin_lead_path(lead), params: { lead: { closing_commission: "100,00" } }
    expect(lead.reload.attributes.slice(*original.keys)).to eq(original)
    expect(flash[:alert]).to include("Selecione uma etapa ganha")
    post close_deal_admin_lead_path(lead), params: { lead: { lead_pipeline_stage_id: another.id, closing_commission: "100,00" } }
    expect(lead.reload).to have_attributes(lead_pipeline_stage_id: another.id, status: another.name, closing_commission_cents: 10000)
  end

  it "recusa etapas de outra conta, outro funil, inativas e não ganhas" do
    lead
    other_tenant = Tenant.create!(name: "Outra conta de fechamento", slug: "other-close-deal")
    other_pipeline = create(:lead_pipeline, tenant: admin.tenant)
    foreign_pipeline = create(:lead_pipeline, tenant: other_tenant)
    choices = [
      create(:lead_pipeline_stage, lead_pipeline: foreign_pipeline, stage_type: "won"),
      create(:lead_pipeline_stage, lead_pipeline: other_pipeline, stage_type: "won"),
      create(:lead_pipeline_stage, lead_pipeline: lead.lead_pipeline, stage_type: "won", active: false),
      lead.lead_pipeline.stages.where(stage_type: "open").first
    ]
    original = lead.attributes.slice("status", "lead_pipeline_stage_id", "closing_commission_cents")
    choices.each do |stage|
      post close_deal_admin_lead_path(lead), params: { lead: { lead_pipeline_stage_id: stage.id, closing_commission: "100,00" } }
      expect(lead.reload.attributes.slice(*original.keys)).to eq(original)
      expect(flash[:alert]).to be_present
    end
  end

  it "não cria etapa nem fecha quando não existe etapa ganha ativa" do
    lead.lead_pipeline.closing_stages.update_all(active: false)
    original = lead.reload.status
    expect { post close_deal_admin_lead_path(lead) }.not_to change(LeadPipelineStage, :count)
    expect(lead.reload.status).to eq(original)
    expect(flash[:alert]).to be_present
  end

  it "compõe o evento de fechamento com a comissão no salvamento e não reenvia" do
    lead
    stage = lead.lead_pipeline.closing_stages.sole
    stage.update!(google_event: "closed", google_event_trigger: "deal_closed")
    WebhookSetting.create!(tenant: admin.tenant, enabled: true, google_conversions_enabled: true, webhook_url: "https://example.test/events")
    allow_any_instance_of(GoogleStageConversionEvent).to receive(:enqueue_delivery)
    lead.update_column(:google_business_type, "venda")
    post close_deal_admin_lead_path(lead), params: { lead: { closing_commission: "100,00" } }
    event = GoogleStageConversionEvent.find_by!(lead_id: lead.id)
    expect(event.payload_data).to include("event_name" => "close_convert_lead", "value" => 100.0)
    expect { post close_deal_admin_lead_path(lead) }.not_to change(GoogleStageConversionEvent, :count)
  end

  it "fecha no funil sem gerar conversão quando os envios Google estão desativados" do
    lead.lead_pipeline.closing_stages.sole.update!(google_event: "closed", google_event_trigger: "deal_closed")
    setting = WebhookSetting.create!(tenant: admin.tenant, enabled: true, google_conversions_enabled: false, webhook_url: "https://example.test/events")
    expect { post close_deal_admin_lead_path(lead) }.not_to change(GoogleStageConversionEvent, :count)
    expect(lead.reload.lead_pipeline_stage.stage_type).to eq("won")
    expect(setting.reload.google_conversions_enabled?).to be(false)
  end

  it "não fecha nem apaga valores diante de uma comissão inválida" do
    original = lead.status
    post close_deal_admin_lead_path(lead), params: { lead: { closing_commission: "-100" } }
    expect(lead.reload.status).to eq(original)
    expect(lead.closing_commission_cents).to be_nil
    expect(flash[:alert]).to be_present
  end
  it "exibe o mesmo campo de fechamento no desktop e no painel mobile" do
    get admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    fields = document.css('input[name="lead[closing_commission]"]')
    stage_fields = document.css('select[name="lead[lead_pipeline_stage_id]"]')
    expect(stage_fields.size).to eq(fields.size)
    expect(stage_fields.map { |field| field["id"] }.uniq.size).to eq(stage_fields.size)
    expect(stage_fields.all? { |field| field["required"] }).to be(true)
    expect(fields.size).to be >= 1
    expect(fields.map { |field| field["id"] }.uniq.size).to eq(fields.size)
  end

end
