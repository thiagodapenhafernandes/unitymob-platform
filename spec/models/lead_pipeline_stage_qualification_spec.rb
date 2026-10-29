require "rails_helper"

RSpec.describe "Disponibilidade da qualificação nas conversões", type: :model do
  let(:pipeline) { create(:lead_pipeline) }

  it "expõe Qualificado para Google, Meta e qualificação adicional sem ativar integrações" do
    [
      { google_event: "qualify_lead", google_event_trigger: "qualified" },
      { meta_conversion_event: "QualifiedLead", meta_event_trigger: "qualified" },
      { google_qualification_enabled: true }
    ].each do |attributes|
      stage = create(:lead_pipeline_stage, lead_pipeline: pipeline, **attributes)
      expect(stage.reload.policy).to have_attributes(qualification_enabled: true)
      expect(stage.policy.qualification_options).to include("qualified")
      expect(stage.policy.tenant_id).to eq(pipeline.tenant_id)
    end
    expect(pipeline.tenant.webhook_settings.where(google_conversions_enabled: true)).to be_empty
  end

  it "impede ocultar o botão e remover Qualificado enquanto houver dependência" do
    stage = create(:lead_pipeline_stage, lead_pipeline: pipeline, google_event: "qualify_lead", google_event_trigger: "qualified")
    policy = stage.reload.policy
    expect(policy.update(qualification_enabled: false)).to be(false)
    expect(policy.errors[:base].join).to include("Exibir qualificação no card")
    policy.reload
    expect(policy.update(qualification_options: ["disqualified"])).to be(false)
    expect(policy.reload.qualification_options).to include("qualified")
  end

  it "preserva opções existentes e permite ocultar após remover todas as dependências" do
    stage = create(:lead_pipeline_stage, lead_pipeline: pipeline)
    policy = stage.create_policy!(tenant: pipeline.tenant, qualification_enabled: false, qualification_options: ["disqualified"])
    stage.update!(meta_conversion_event: "Lead", meta_event_trigger: "qualified")
    expect(policy.reload.qualification_options).to match_array(%w[disqualified qualified])
    stage.update!(meta_event_trigger: "stage_entered")
    expect(policy.reload.update(qualification_enabled: false, qualification_options: ["disqualified"])).to be(true)
  end

  it "não exige qualificação para entrada na etapa nem modifica outra conta" do
    other_tenant = Tenant.create!(name: "Outra conta", slug: "qualification-#{SecureRandom.hex(4)}")
    other = create(:lead_pipeline, tenant: other_tenant)
    stage = create(:lead_pipeline_stage, lead_pipeline: other)
    policy = stage.create_policy!(tenant: other.tenant, qualification_enabled: false)
    create(:lead_pipeline_stage, lead_pipeline: pipeline, google_event: "qualify_lead", google_event_trigger: "stage_entered")
    expect(policy.reload.qualification_enabled).to be(false)
  end
end
