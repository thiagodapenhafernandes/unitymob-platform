require "rails_helper"
require Rails.root.join("db/migrate/20261113150000_add_whatsapp_campaign_source_to_distribution_rules")

RSpec.describe AddWhatsappCampaignSourceToDistributionRules do
  it "habilita apenas os destinos de campanhas da mesma conta, em ambos os formatos de botões" do
    admin = create(:admin_user, :admin)
    template = WhatsappTemplate.create!(name: "backfill_campaign_source", status: "APPROVED", body: "Olá")
    campaign = WhatsappCampaign.create!(name: "Legada", whatsapp_template: template, created_by: admin)
    array_rule, hash_rule, unused_rule = Array.new(3) { create(:distribution_rule, tenant: admin.tenant) }
    foreign = Tenant.create!(name: "Outra conta", slug: "backfill-campaign-#{SecureRandom.hex(4)}")
    foreign_rule = create(:distribution_rule, tenant: foreign)
    campaign.update_columns(response_decisions: { buttons: [
      { action: "generate_lead", distribution_rule_id: array_rule.id.to_s },
      { action: "generate_lead", distribution_rule_id: foreign_rule.id.to_s }
    ] })
    other_campaign = WhatsappCampaign.create!(name: "Legada hash", whatsapp_template: template, created_by: admin)
    other_campaign.update_columns(response_decisions: { buttons: { "0" => { action: "generate_lead", distribution_rule_id: hash_rule.id } } })

    migration = described_class.new
    # A coluna já existe no banco de teste; executa o backfill real.
    allow(migration).to receive(:connection).and_return(ActiveRecord::Base.connection)
    allow(ActiveRecord::Base.connection).to receive(:add_column)
    migration.up

    expect(array_rule.reload.source_whatsapp_campaign?).to be(true)
    expect(hash_rule.reload.source_whatsapp_campaign?).to be(true)
    expect(unused_rule.reload.source_whatsapp_campaign?).to be(false)
    expect(foreign_rule.reload.source_whatsapp_campaign?).to be(false)
  end
end
