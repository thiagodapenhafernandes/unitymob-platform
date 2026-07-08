require "rails_helper"

RSpec.describe "Sync job tenant actor resolution" do
  include ActiveJob::TestHelper

  def create_tenant_with_admin(label)
    tenant = Tenant.create!(name: "#{label} #{SecureRandom.hex(3)}", slug: "#{label.parameterize}-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    [tenant, admin]
  end

  it "reconhece triggered_by apenas quando pertence ao tenant do DwvSyncJob" do
    tenant, admin = create_tenant_with_admin("DWV actor")
    other_tenant, other_admin = create_tenant_with_admin("DWV other actor")
    job = DwvSyncJob.new

    expect(job.send(:resolve_triggered_by, tenant: tenant, triggered_by_id: admin.id)).to eq(admin)
    expect(job.send(:resolve_triggered_by, tenant: tenant, triggered_by_id: other_admin.id)).to be_nil
    expect(other_tenant).to be_present
  end

  it "não usa Tenant.default como fallback silencioso nos jobs de sync" do
    expect(DwvSyncJob.new.send(:resolve_tenant, tenant_id: nil, triggered_by_id: nil)).to be_nil
    expect(LoftSyncJob.new.send(:resolve_tenant, tenant_id: nil, triggered_by_id: nil)).to be_nil
    expect(LoftImagesSyncJob.new.send(:resolve_tenant, tenant_id: nil, triggered_by_id: nil)).to be_nil
  end

  it "reconhece triggered_by apenas quando pertence ao tenant do LoftSyncJob" do
    tenant, admin = create_tenant_with_admin("Loft actor")
    _other_tenant, other_admin = create_tenant_with_admin("Loft other actor")
    job = LoftSyncJob.new

    expect(job.send(:resolve_triggered_by, tenant: tenant, triggered_by_id: admin.id)).to eq(admin)
    expect(job.send(:resolve_triggered_by, tenant: tenant, triggered_by_id: other_admin.id)).to be_nil
  end

  it "reconhece triggered_by apenas quando pertence ao tenant do LoftImagesSyncJob" do
    tenant, admin = create_tenant_with_admin("Loft images actor")
    _other_tenant, other_admin = create_tenant_with_admin("Loft images other actor")
    job = LoftImagesSyncJob.new

    expect(job.send(:resolve_triggered_by, tenant: tenant, triggered_by_id: admin.id)).to eq(admin)
    expect(job.send(:resolve_triggered_by, tenant: tenant, triggered_by_id: other_admin.id)).to be_nil
  end

  it "publica fotos no tenant informado e nao atribui admin_user de outra conta no log" do
    tenant, = create_tenant_with_admin("Storage actor")
    _other_tenant, other_admin = create_tenant_with_admin("Storage other actor")
    publisher = instance_double(Storage::PublicPropertyPhotoPublisher, publish_all: { processed: 0 })
    logged_messages = []

    allow(Storage::PublicPropertyPhotoPublisher).to receive(:new).with(tenant: tenant).and_return(publisher)
    allow(Storage::PublicPropertyPhotoPublisher).to receive(:result_message).and_return("sem imóveis")
    allow(Rails.logger).to receive(:info) { |message| logged_messages << message }

    Storage::PublishPublicPropertyPhotosJob.perform_now(other_admin.id, tenant.id)

    expect(Storage::PublicPropertyPhotoPublisher).to have_received(:new).with(tenant: tenant)
    expect(logged_messages.join).to include("admin_user_id=")
    expect(logged_messages.join).not_to include("admin_user_id=#{other_admin.id}")
  end

  it "agenda sync Loft para cada tenant ativo" do
    Tenant.create!(name: "Tenant agenda Loft #{SecureRandom.hex(3)}", slug: "tenant-agenda-loft-#{SecureRandom.hex(3)}")
    Tenant.create!(name: "Outro agenda Loft #{SecureRandom.hex(3)}", slug: "outro-agenda-loft-#{SecureRandom.hex(3)}")
    Setting.set("loft_schedule_enabled", "true", "teste")
    Setting.set("loft_schedule_cron", "* * * * *", "teste")
    Setting.set(Loft::ScheduledSyncService::LAST_SLOT_KEY, "", "teste")

    expect {
      Loft::ScheduledSyncService.new.call(now: Time.zone.local(2026, 6, 29, 9, 0, 0))
    }.to have_enqueued_job(LoftSyncJob).exactly(Tenant.active.count).times
  end

  it "agenda sync DWV incremental apenas para tenants com integração habilitada" do
    enabled_tenant = Tenant.create!(name: "Tenant agenda DWV #{SecureRandom.hex(3)}", slug: "tenant-agenda-dwv-#{SecureRandom.hex(3)}")
    disabled_tenant = Tenant.create!(name: "Outro agenda DWV #{SecureRandom.hex(3)}", slug: "outro-agenda-dwv-#{SecureRandom.hex(3)}")
    Setting.set("dwv_enabled", "true", "teste", tenant: enabled_tenant)
    Setting.set("dwv_api_token", "token-dwv", "teste", tenant: enabled_tenant)
    Setting.set("dwv_enabled", "false", "teste", tenant: disabled_tenant)

    expect {
      DwvSyncAllTenantsJob.perform_now(mode: "incremental", last_updates: "07/07/2026")
    }.to have_enqueued_job(DwvSyncJob).with(
      hash_including(
        mode: "incremental",
        last_updates: "07/07/2026",
        tenant_id: enabled_tenant.id
      )
    ).once
  end

  it "mantém compatibilidade com o recurring legado do DWV incremental" do
    expect(DwvSyncAllTenantsJob).to receive(:perform_now).with(
      hash_including(mode: "incremental", last_updates: "07/07/2026")
    )

    DwvIncrementalSyncJob.perform_now(last_updates: "07/07/2026")
  end
end
