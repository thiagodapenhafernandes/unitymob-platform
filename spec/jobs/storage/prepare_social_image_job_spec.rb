require "rails_helper"

RSpec.describe Storage::PrepareSocialImageJob, type: :job do
  it "uses the isolated media queue" do
    expect(described_class.new.queue_name).to eq("media")
  end

  it "processes and publishes the social variant inside the tenant" do
    tenant = instance_double(Tenant, id: 7)
    habitations = double("habitations")
    habitation = instance_double(Habitation)
    photos = double("photos")
    attachments = double("attachments")
    attachment = instance_double(ActiveStorage::Attachment)
    blob = instance_double(ActiveStorage::Blob, image?: true)
    variant_blob = instance_double(ActiveStorage::Blob)
    variant_image = double("variant image", attached?: true, blob: variant_blob)
    variant = double("variant", image: variant_image)

    allow(Tenant).to receive(:find_by).with(id: 7).and_return(tenant)
    allow(tenant).to receive(:habitations).and_return(habitations)
    allow(habitations).to receive(:find_by).with(id: 11).and_return(habitation)
    allow(habitation).to receive(:photos).and_return(photos)
    allow(photos).to receive(:attachments).and_return(attachments)
    allow(attachments).to receive(:includes).with(:blob).and_return(attachments)
    allow(attachments).to receive(:find_by).with(id: 13).and_return(attachment)
    allow(attachment).to receive(:blob).and_return(blob)
    allow(blob).to receive(:variant).with(resize_to_limit: [1200, 1200]).and_return(variant)
    allow(variant).to receive(:processed).and_return(variant)
    allow(Storage::PublicPropertyPhoto).to receive(:publish_attachment!).with(attachment)
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!).with(variant_blob, raise_errors: true)

    described_class.perform_now(
      11,
      13,
      tenant_id: 7,
      transformations: { "resize_to_limit" => [1200, 1200] }
    )

    expect(Storage::PublicPropertyPhoto).to have_received(:publish_attachment!).with(attachment)
    expect(Storage::PublicPropertyPhoto).to have_received(:publish_blob!).with(variant_blob, raise_errors: true)
  end

  it "rejects jobs without a valid tenant" do
    allow(Tenant).to receive(:find_by).with(id: 999).and_return(nil)

    expect do
      described_class.perform_now(11, 13, tenant_id: 999, transformations: {})
    end.to raise_error(ArgumentError, "Tenant obrigatorio para preparar imagem social")
  end
end
