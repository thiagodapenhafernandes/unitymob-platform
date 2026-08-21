require "rails_helper"

RSpec.describe Storage::BlobAuditRecorder do
  it "registra contexto do blob e do anexo sem depender do objeto continuar existindo" do
    tenant = Tenant.default
    admin_user = create(:admin_user, tenant: tenant)
    habitation = create(:habitation, tenant: tenant, codigo: "AUDIT-BLOB-1", address_attributes: address_attributes)
    habitation.photos.attach(
      io: StringIO.new("image"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )
    attachment = habitation.photos.attachments.first

    Current.set(tenant: tenant, admin_user: admin_user, request_ip: "127.0.0.1", request_user_agent: "RSpec") do
      described_class.record!(
        blob: attachment.blob,
        action: "purge_requested",
        source: "spec",
        attachment: attachment,
        metadata: { "reason" => "test" }
      )
    end

    log = ActiveStorageBlobAuditLog.last
    expect(log).to have_attributes(
      tenant_id: tenant.id,
      admin_user_id: admin_user.id,
      blob_id: attachment.blob.id,
      attachment_id: attachment.id,
      record_type: "Habitation",
      record_id: habitation.id,
      attachment_name: "photos",
      action: "purge_requested",
      source: "spec",
      key: attachment.blob.key,
      filename: "foto.jpg",
      content_type: "image/jpeg",
      service_name: attachment.blob.service_name,
      user_agent: "RSpec"
    )
    expect(log.ip.to_s).to eq("127.0.0.1")
    expect(log.metadata).to eq("reason" => "test")
  end

  def address_attributes
    {
      logradouro: "Rua Auditoria",
      bairro: "Centro",
      cidade: "Itapema",
      uf: "SC"
    }
  end
end
