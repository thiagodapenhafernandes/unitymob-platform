require "rails_helper"

RSpec.describe DistributionRule do
  it "preserva exceções por regra e impede reinclusão automática sem alterar leads" do
    rule = create(:distribution_rule, auto_add_forms: true, excluded_meta_form_ids: ["excluded"], meta_forms: ["excluded", "included"])
    other = create(:distribution_rule, tenant: rule.tenant, auto_add_forms: true)
    expect(rule.meta_forms).to eq(["included"])
    stale = described_class.find(rule.id)
    rule.update!(excluded_meta_form_ids: ["excluded", "blocked-later"])
    stale.add_auto_meta_forms!(["blocked-later"])
    expect(stale.reload.meta_forms).not_to include("blocked-later")
    allow_any_instance_of(Lead).to receive(:route_lead)
    lead = create(:lead, tenant: rule.tenant, distribution_rule: rule)
    original_lead = lead.attributes
    rule.add_auto_meta_forms!(["excluded", "new"])
    expect(lead.reload.attributes).to eq(original_lead)
    expect(rule.reload.meta_forms).to eq(["included", "new"])
    other.add_auto_meta_forms!(["excluded"])
    expect(other.reload.meta_forms).to eq(["excluded"])
    rule.update!(auto_add_forms: false, meta_forms: ["excluded"])
    expect(rule.excluded_meta_form_ids).to eq(["excluded", "blocked-later"])
    expect(rule.meta_form_excluded?("excluded")).to eq(false)
    rule.update!(auto_add_forms: true)
    expect(rule.meta_forms).to be_empty
    rule.update!(excluded_meta_form_ids: [])
    rule.add_auto_meta_forms!(["excluded"])
    expect(rule.reload.meta_forms).to eq(["excluded"])
  end
end
