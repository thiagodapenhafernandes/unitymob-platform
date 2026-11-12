require "rails_helper"
require "timeout"

RSpec.describe "Agenda C2S concorrente" do
  self.use_transactional_tests = false

  it "mantém uma tarefa por ação quando dois jobs atualizam o mesmo lead" do
    tenant = Tenant.default
    owner = create(:admin_user, tenant: tenant)
    integration = create(:external_lead_integration, tenant: tenant, connected_by_admin_user: owner,
      mirror_c2s_owners: true, seller_mappings: { "concurrent-seller" => owner.id })
    lead = build(:lead, tenant: tenant, admin_user: owner, external_lead_integration: integration,
      external_lead_id: "concurrent-#{SecureRandom.hex(8)}")
    lead.skip_automatic_routing = true
    lead.save!
    payload = { "id" => lead.external_lead_id, "attributes" => {
      "updated_at" => Time.current.iso8601,
      "seller" => { "id" => "concurrent-seller", "name" => owner.name, "email" => owner.email },
      "schedulated_actions" => [{ "id" => "concurrent-action", "name" => "Retorno",
        "due_at" => 1.day.from_now.iso8601, "status" => "Em aberto" }]
    } }
    allow_any_instance_of(ExternalLeadMigration::LeadEnrichment).to receive(:existing_task_for).and_wrap_original do |original, *args|
      found = original.call(*args)
      sleep 0.3 unless found
      found
    end
    ready, start = Queue.new, Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          ExternalLeadMigration::LeadUpsert.call(integration: ExternalLeadIntegration.find(integration.id), payload: payload.deep_dup)
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      workers.each(&:value)
    end

    expect(lead.tasks.count).to eq(1)
    expect(lead.activities.where(kind: "external_scheduled_action").count).to eq(1)
  ensure
    workers&.each { |worker| worker.kill if worker.alive?; worker.join }
    if lead&.persisted?
      lead.tasks.destroy_all
      lead.destroy!
    end
    integration&.destroy!
    owner&.destroy!
  end
end
