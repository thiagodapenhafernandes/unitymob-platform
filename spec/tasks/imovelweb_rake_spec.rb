require "rails_helper"
require "rake"

RSpec.describe "Imovelweb support tasks" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("imovelweb:prepare") }
  around do |example|
    keys = %w[TENANT_ID CONNECTION_ID RECEIPT_ID APPLY ENVIRONMENT IMOVELWEB_RECEIVING_ENABLED]
    saved = ENV.to_h.slice(*keys)
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
    %w[prepare retry_receipt].each { |name| Rake::Task["imovelweb:#{name}"].reenable }
  end

  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:connection) { ImovelwebConnection.create!(tenant: tenant, client_code: "task-client", enabled: true, authorized_at: Time.current) }
  let(:receipt) { connection.imovelweb_lead_receipts.create!(event_id: "task-event", event_type: "CONTACTO", payload: '{}', received_at: Time.current, status: "quarantined", reason: "unknown_listing") }

  it "prepares a sandbox connection disabled without network or credentials" do
    ENV["TENANT_ID"] = tenant.id.to_s
    expect { Rake::Task["imovelweb:prepare"].invoke }.to output(/enabled=false/).to_stdout
    prepared = ImovelwebConnection.last
    expect(prepared.tenant).to eq(tenant)
    expect(prepared.environment).to eq("sandbox")
    expect(prepared.enabled).to eq(false)
    expect(prepared.authorized_at).to be_nil
  end

  it "dry-runs a selected receipt, then enqueues only that receipt with APPLY" do
    ENV["IMOVELWEB_RECEIVING_ENABLED"] = "true"
    ENV["TENANT_ID"] = tenant.id.to_s
    ENV["CONNECTION_ID"] = connection.id.to_s
    ENV["RECEIPT_ID"] = receipt.id.to_s
    task = Rake::Task["imovelweb:retry_receipt"]
    expect { task.invoke }.to output(/apply=false/).to_stdout
    expect(receipt.reload.status).to eq("quarantined")
    ENV["APPLY"] = "true"
    task.reenable
    expect { expect { task.invoke }.to output(/apply=true/).to_stdout }.to have_enqueued_job(ImovelwebLeadProcessingJob).with(receipt.id)
    expect(receipt.reload.status).to eq("pending")
  end

  it "rejects a connection outside the supplied tenant" do
    ENV["TENANT_ID"] = Tenant.create!(name: "Outro", slug: "iw-task-other").id.to_s
    ENV["CONNECTION_ID"] = connection.id.to_s
    ENV["RECEIPT_ID"] = receipt.id.to_s
    expect { Rake::Task["imovelweb:retry_receipt"].invoke }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
