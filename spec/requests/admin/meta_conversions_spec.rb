require "rails_helper"

RSpec.describe "Admin::MetaConversions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:meta_lead) { create(:lead, tenant: tenant, attribution_channel: "meta_ads", admin_user: admin) }

  before do
    host! "localhost"
    sign_in admin
    MetaConversionConfig.create!(tenant: tenant, datasets: [{ "id" => "999" }])
    create(:user_meta_integration, admin_user: admin, tenant: tenant, access_token: "tok",
                                   ad_accounts: { "123" => "Conta Anúncios" })
  end

  def stub_datasets(pixels)
    allow_any_instance_of(Facebook::MetaService).to receive(:ad_account_pixels).and_return(pixels)
  end

  it "lista os datasets das contas conectadas no form" do
    stub_datasets([{ "id" => "111", "name" => "Pixel Loja" }])

    get conversion_config_form_admin_meta_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pixel Loja (111)")
  end

  it "salva múltiplos datasets com nomes resolvidos" do
    stub_datasets([{ "id" => "111", "name" => "Pixel Loja" }, { "id" => "222", "name" => "Pixel Filial" }])

    patch conversion_config_admin_meta_integrations_path,
          params: { meta_conversion_config: { dataset_ids: ["111", "222"], test_event_code: "T1", enabled: "1" } }

    expect(response).to redirect_to(admin_meta_integrations_path)
    config = MetaConversionConfig.for_tenant(tenant).first
    expect(config.dataset_list).to eq([{ "id" => "111", "name" => "Pixel Loja" },
                                       { "id" => "222", "name" => "Pixel Filial" }])
    expect(config.test_event_code).to eq("T1")
  end

  it "aceita IDs manuais quando a descoberta falha" do
    MetaConversionConfig.for_tenant(tenant).first.update_column(:datasets, [])
    stub_datasets([])

    get conversion_config_form_admin_meta_integrations_path
    expect(response.body).to include("digite o código se você já o tem")

    patch conversion_config_admin_meta_integrations_path,
          params: { meta_conversion_config: { dataset_ids_manual: "333, 444", enabled: "1" } }

    config = MetaConversionConfig.for_tenant(tenant).first
    expect(config.dataset_list).to eq([{ "id" => "333", "name" => "333" },
                                       { "id" => "444", "name" => "444" }])
  end

  it "rejeita config CAPI sem dataset" do
    stub_datasets([{ "id" => "111", "name" => "Pixel Loja" }])

    patch conversion_config_admin_meta_integrations_path,
          params: { meta_conversion_config: { dataset_ids: [], enabled: "1" } }

    expect(response).to redirect_to(admin_meta_integrations_path)
    expect(flash[:alert]).to be_present
  end

  def enable_qualification!(stage)
    policy = stage.policy || create(:lead_pipeline_stage_policy, tenant: tenant, lead_pipeline_stage: stage)
    policy.update!(qualification_enabled: true)
  end

  it "enfileira QualifiedLead ao qualificar lead de origem Meta" do
    enable_qualification!(meta_lead.lead_pipeline_stage)

    expect do
      patch admin_lead_path(meta_lead), params: { lead: { manager_qualification_status: "qualified" } }
    end.to have_enqueued_job(MetaConversionJob).with(tenant.id, meta_lead.id, "QualifiedLead", kind_of(String), kind_of(String), nil)
  end

  it "não enfileira qualificação de lead de outra origem" do
    other = create(:lead, tenant: tenant, origin: "site", admin_user: admin)
    enable_qualification!(other.lead_pipeline_stage)

    expect do
      patch admin_lead_path(other), params: { lead: { manager_qualification_status: "qualified" } }
    end.not_to have_enqueued_job(MetaConversionJob)
  end

  it "enfileira o evento mapeado na etapa de destino" do
    visit_stage = create(:lead_pipeline_stage, lead_pipeline: meta_lead.lead_pipeline, tenant: tenant,
                                               name: "Visita feita", stage_type: "open",
                                               meta_conversion_event: "Schedule")
    create(:lead_pipeline_stage_transition, tenant: tenant,
           lead_pipeline_stage: meta_lead.lead_pipeline_stage, next_stage: visit_stage)

    expect do
      patch admin_lead_path(meta_lead), params: { lead: { lead_pipeline_stage_id: visit_stage.id } }
    end.to have_enqueued_job(MetaConversionJob).with(tenant.id, meta_lead.id, "Schedule", kind_of(String), kind_of(String), nil)
  end

  it "não enfileira ao mover para etapa sem mapeamento" do
    plain = create(:lead_pipeline_stage, lead_pipeline: meta_lead.lead_pipeline, tenant: tenant,
                                         name: "Etapa comum", stage_type: "open", meta_conversion_event: nil)
    create(:lead_pipeline_stage_transition, tenant: tenant,
           lead_pipeline_stage: meta_lead.lead_pipeline_stage, next_stage: plain)

    expect do
      patch admin_lead_path(meta_lead), params: { lead: { lead_pipeline_stage_id: plain.id } }
    end.not_to have_enqueued_job(MetaConversionJob)
  end

  it "enfileira Schedule ao concluir visita" do
    appointment = create(:appointment, tenant: tenant, lead: meta_lead, admin_user: admin,
                                     kind: "visita", status: "agendado")

    expect do
      patch admin_appointment_path(appointment), params: { appointment: { status: "realizado" } }
    end.to have_enqueued_job(MetaConversionJob).with(tenant.id, meta_lead.id, "Schedule", kind_of(String), kind_of(String), nil)
  end

  it "não enfileira visita de outro tipo nem lead de outra origem" do
    meeting = create(:appointment, tenant: tenant, lead: meta_lead, admin_user: admin,
                                 kind: "reuniao", status: "agendado")
    other = create(:lead, tenant: tenant, origin: "site", admin_user: admin)
    other_visit = create(:appointment, tenant: tenant, lead: other, admin_user: admin,
                                     kind: "visita", status: "agendado")

    expect do
      patch admin_appointment_path(meeting), params: { appointment: { status: "realizado" } }
      patch admin_appointment_path(other_visit), params: { appointment: { status: "realizado" } }
    end.not_to have_enqueued_job(MetaConversionJob)
  end
end
