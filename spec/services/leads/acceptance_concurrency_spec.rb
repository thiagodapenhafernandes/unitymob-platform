require "rails_helper"
require "timeout"

RSpec.describe "Aceite concorrente entre canais" do
  self.use_transactional_tests = false

  it "mantém um vencedor e uma única atividade quando admin e WhatsApp disputam" do
    tenant = Tenant.create!(name: "Aceite concorrente", slug: "acceptance-race-#{SecureRandom.hex(5)}")
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::AuditChangeRecorder).to receive(:record_create!)
    allow(Leads::AuditChangeRecorder).to receive(:record_destroy!)
    actors = 2.times.map { create(:admin_user, :field_agent, tenant: tenant) }
    lead = create(:lead, tenant: tenant, admin_user: nil, status: :waiting_acceptance)
    ready, start = Queue.new, Queue.new
    workers = actors.each_with_index.map do |actor, index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          Leads::Acceptance.call(tenant: tenant, lead: tenant.leads.find(lead.id), actor: actor,
            metadata: { via: index.zero? ? "system" : "whatsapp" },
            claim_statuses: [Lead.status_value(:waiting_acceptance)])
        end
      end
    end
    results = Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      workers.map(&:value)
    end
    expect(results).to match_array(%i[accepted taken])
    expect(actors.map(&:id)).to include(lead.reload.admin_user_id)
    expect(lead.activities.where(kind: "accepted").count).to eq(1)
  ensure
    workers&.each { |worker| worker.kill if worker.alive?; worker.join }
    if tenant
      tenant.leads.destroy_all
      AutomationEvent.where(tenant_id: tenant.id).delete_all
      tenant.distribution_rules.destroy_all
      tenant.admin_users.destroy_all
      LeadPipelineStageTransition.where(tenant_id: tenant.id).delete_all
      tenant.lead_pipelines.destroy_all
      Profile.where(tenant_id: tenant.id).delete_all
      tenant.lead_setting&.destroy!
      AttributeOption.where(tenant_id: tenant.id).delete_all
      tenant.reload.destroy!
    end
  end
end
