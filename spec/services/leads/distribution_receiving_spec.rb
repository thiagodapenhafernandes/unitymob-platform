require "rails_helper"

RSpec.describe "Recebimento por formulário Meta", type: :service do
  let(:tenant) { Tenant.default }
  let(:integration) { create(:user_meta_integration, tenant: tenant, selected_page_ids: ["receiving-page"]) }
  let!(:page) { create(:meta_facebook_page, user_meta_integration: integration, page_id: "receiving-page") }
  let(:agent) { create(:admin_user, tenant: tenant) }
  let!(:general) { create(:distribution_rule, tenant: tenant, name: "Equipe vendas", business_type: :todos,
    source_meta: true, source_site: false, meta_page_ids: [page.page_id], auto_add_forms: true,
    excluded_meta_form_ids: ["notre-dame"]) }
  let!(:specific) { create(:distribution_rule, tenant: tenant, name: "AUGT", business_type: :todos,
    source_meta: true, source_site: false, meta_page_ids: [page.page_id], meta_forms: ["notre-dame"]) }
  before do
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    allow(Automation::Dispatcher).to receive(:dispatch)
    create(:distribution_rule_agent, distribution_rule: general, admin_user: agent)
    create(:distribution_rule_agent, distribution_rule: specific, admin_user: agent)
  end
  around { |example| Current.set(tenant: tenant) { example.run } }

  def entry(form: "notre-dame", **attributes)
    create(:lead, tenant: tenant, origin: "Facebook Lead Ads", product: "Contato do formulário",
      other_information: {"meta_page_id" => page.page_id, "meta_form_id" => form}, **attributes)
  end

  it "entrega entrada indefinida ao formulário específico e mantém sua classificação" do
    lead = entry
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload).to have_attributes(admin_user_id: agent.id, distribution_rule_id: specific.id)
    expect(lead.other_information).not_to have_key("business_type")
    expect(lead.activities.find_by!(kind: "distributed").metadata).to include(
      "receiving" => "todos", "entry_nature" => "unknown",
      "meta_scope" => {"auto_add_forms" => false, "page_ids" => [page.page_id], "form_ids" => ["notre-dame"], "excluded_form_ids" => []})
  end

  it "recebe um formulário novo automaticamente sem mudar as exceções" do
    lead = entry(form: "new-form")
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload.distribution_rule_id).to eq(general.id)
    expect(general.reload.excluded_meta_form_ids).to eq(["notre-dame"])
  end

  it "prefere seleção explícita mesmo sem exclusão na automática" do
    general.update!(excluded_meta_form_ids: [])
    lead = entry
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload.distribution_rule_id).to eq(specific.id)
  end

  it "mantém filtros adicionais mesmo com Todos" do
    specific.update!(custom_filters: [{key: "product", value: "Apartamento"}])
    lead = entry
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.distribution_rule_id).to be_nil
  end

  it "não cai na automática excluída se a específica não aceita a modalidade" do
    specific.update!(business_type: :venda)
    lead = entry
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.distribution_rule_id).to be_nil
  end

  it "mantém pendente conflito legado e não o contorna pela contingência" do
    other = create(:distribution_rule, tenant: tenant, source_meta: true, source_site: false, business_type: :todos,
      meta_page_ids: [page.page_id], meta_forms: ["other-form"])
    other.update_columns(meta_forms: ["notre-dame"])
    LeadSetting.instance(tenant: tenant).update!(default_distribution_rule: general)
    lead = entry
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.activities.where(kind: "distribution_failed").last.metadata).to include(
      "reason" => "conflicting_rules", "conflicting_rule_ids" => [specific.id, other.id])
    expect(Leads::ContingencyService.default!(lead)).to be(false)
    expect(lead.reload.contingency_forwarded_at).to be_nil
  end

  it "impede contingência para formulário excluído mesmo com sincronização desligada" do
    specific.update!(contingency_enabled: true, contingency_rule: general, contingency_triggers: ["unavailable"])
    specific.distribution_rule_agents.destroy_all
    general.update!(auto_add_forms: false, meta_forms: ["notre-dame"])
    lead = entry
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload).to have_attributes(distribution_rule_id: specific.id, admin_user_id: nil, contingency_forwarded_at: nil)
  end
  it "usa o formulário da consulta atual na contingência, preservando a origem antiga" do
    specific.update!(contingency_enabled: true, contingency_rule: general, contingency_triggers: ["unavailable"])
    specific.distribution_rule_agents.destroy_all
    previous = entry(form: "old-form", status: :concluido)
    inquiry = build(:lead, tenant: tenant, origin: "Facebook Lead Ads", product: nil,
      other_information: {"meta_page_id" => page.page_id, "meta_form_id" => "notre-dame"})
    Leads::DistributorService.redistribute(previous, inquiry: inquiry)
    expect(previous.reload).to have_attributes(admin_user_id: nil, distribution_rule_id: specific.id, contingency_forwarded_at: nil)
    expect(previous.other_information["meta_form_id"]).to eq("old-form")
    expect(previous.other_information.dig("distribution_entry", "meta_form_id")).to eq("notre-dame")
  end

  it "não deixa conflito antigo bloquear a contingência de um ciclo novo válido" do
    specific.update!(contingency_enabled: true, contingency_rule: general, contingency_triggers: ["unavailable"])
    specific.distribution_rule_agents.destroy_all
    general.update!(excluded_meta_form_ids: [])
    previous = entry(status: :concluido)
    previous.activities.create!(kind: "distribution_failed", metadata: {reason: "conflicting_rules"}, created_at: 1.minute.ago)
    inquiry = build(:lead, tenant: tenant, origin: "Facebook Lead Ads", product: nil,
      other_information: {"meta_page_id" => page.page_id, "meta_form_id" => "notre-dame"})
    Leads::DistributorService.redistribute(previous, inquiry: inquiry)
    expect(previous.reload).to have_attributes(admin_user_id: agent.id, distribution_rule_id: general.id)
    expect(previous.contingency_forwarded_at).to be_present
  end

end
