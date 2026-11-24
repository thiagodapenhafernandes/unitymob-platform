require "rails_helper"

RSpec.describe Lead, type: :model do
  let(:tenant) { Tenant.create!(name: "Conta #{SecureRandom.hex(4)}", slug: "conta-#{SecureRandom.hex(4)}").tap { |account| account.lead_pipelines.update_all(default_general: false, default_for_sale: false, default_for_rental: false) } }
  let!(:general) { create(:lead_pipeline, tenant: tenant, default_general: true) }
  let!(:initial) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: general, name: "Entrada", position: 0) }
  let!(:sale) { create(:lead_pipeline, tenant: tenant, kind: "sale", default_for_sale: true) }
  let!(:sale_stage) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: sale, name: "Entrada venda", position: 0) }
  let!(:rental) { create(:lead_pipeline, tenant: tenant, kind: "rental", default_for_rental: true) }
  let!(:rental_stage) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: rental, name: "Entrada locação", position: 0) }
  let!(:daily) { create(:lead_pipeline, tenant: tenant, kind: "daily", default_for_daily: true) }
  let!(:daily_stage) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: daily, name: "Entrada diária", position: 0) }

  def new_lead(**attributes)
    build(:lead, tenant: tenant, lead_pipeline: general, lead_pipeline_stage: initial, status: initial.name,
      skip_automatic_routing: true, **attributes)
  end

  { "venda" => :sale, "locacao" => :rental, "diaria" => :daily }.each do |type, pipeline|
    it "seleciona o funil de #{type} pela classificação da entrada" do
      lead = new_lead(other_information: { "business_type" => type })
      lead.save!
      expect(lead.reload.lead_pipeline).to eq(public_send(pipeline))
      expect(lead.lead_pipeline_stage).to eq(public_send(pipeline).default_stage)
    end
  end

  it "mantém o padrão geral quando o negócio não é identificado" do
    lead = new_lead
    lead.save!
    expect(lead.reload.lead_pipeline).to eq(general)
  end

  it "preserva o funil existente em alterações sem mudança de modalidade" do
    lead = new_lead(other_information: { "business_type" => "venda" })
    lead.save!
    lead.update_columns(lead_pipeline_id: general.id, lead_pipeline_stage_id: initial.id, status: initial.name)
    lead.reload.update!(notes: "Contato realizado")
    expect(lead.reload.lead_pipeline).to eq(general)
  end

  it "mantém a etapa equivalente ao mudar o tipo de negócio" do
    equivalent = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: rental, name: sale_stage.name)
    lead = new_lead(business_type: "venda")
    lead.save!
    lead.update!(business_type: "locacao")
    expect(lead.reload.lead_pipeline).to eq(rental)
    expect(lead.lead_pipeline_stage).to eq(equivalent)
  end

  it "exige escolha sem etapa equivalente e mantém o registro salvo intacto" do
    lead = new_lead(business_type: "venda")
    lead.save!
    expect(lead.update(business_type: "locacao")).to be(false)
    expect(lead.errors[:lead_pipeline_stage].join).to include("deve ser escolhida")
    expect(lead.reload.lead_pipeline).to eq(sale)
    expect(lead.business_type).to eq("venda")
  end

  it "aceita a escolha explícita de uma etapa do novo funil" do
    lead = new_lead(business_type: "venda")
    lead.save!
    lead.update!(business_type: "diaria", lead_pipeline: daily, lead_pipeline_stage: daily_stage, status: daily_stage.name)
    expect(lead.reload.lead_pipeline_stage).to eq(daily_stage)
  end

  it "não usa funil configurado em outra conta" do
    daily.update!(default_for_daily: false)
    create(:lead_pipeline, tenant: Tenant.create!(name: "Conta #{SecureRandom.hex(4)}", slug: "conta-#{SecureRandom.hex(4)}"), kind: "daily", default_for_daily: true)
    lead = new_lead(business_type: "diaria")
    expect(lead.save).to be(false)
    expect(lead.errors[:business_type]).to include("não tem um funil ativo configurado nesta conta")
  end

  it "preserva o funil de integração compatível com a modalidade e a etapa importada" do
    mapped = create(:lead_pipeline, tenant: tenant, kind: "rental")
    mapped_stage = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: mapped, name: "Atendimento integrado")
    lead = new_lead(other_information: { "business_type" => "locacao" }, lead_pipeline: mapped, lead_pipeline_stage: mapped_stage, status: mapped_stage.name)
    lead.save!
    expect(lead.reload.lead_pipeline_stage).to eq(mapped_stage)
  end

  it "rejeita um tipo de negócio manual desconhecido" do
    lead = new_lead(business_type: "outro")
    expect(lead.save).to be(false)
    expect(lead.errors[:business_type]).to include("é inválido")
  end

  it "não usa funil inativo" do
    daily.update!(active: false)
    expect(LeadPipeline.for_business_type(tenant: tenant, business_type: "diaria")).to be_nil
  end
end
