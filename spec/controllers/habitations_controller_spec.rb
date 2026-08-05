require "rails_helper"

RSpec.describe HabitationsController, type: :controller do
  include ActiveJob::TestHelper

  describe "#ensure_social_photo_public!" do
    it "keeps link generation synchronous while preparing a missing variant on media" do
      habitation = instance_double(Habitation, id: 11, tenant_id: 7)
      attachment = instance_double(ActiveStorage::Attachment, id: 13)
      blob = instance_double(ActiveStorage::Blob, image?: true)
      variant_image = double("variant image", attached?: false)
      variant = double("variant", image: variant_image)

      allow(habitation).to receive(:primary_image_source).and_return({ attachment: attachment })
      allow(attachment).to receive(:blob).and_return(blob)
      allow(blob).to receive(:variant).with(resize_to_limit: [1200, 1200]).and_return(variant)
      allow(Storage::PublicPropertyPhoto).to receive(:publish_attachment!).with(attachment)
      allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_attachment).with(attachment).and_return("https://cdn.example.com/foto-original.png")
      allow(controller).to receive(:social_image_url_accessible?).with("https://cdn.example.com/foto-original.png").and_return(true)

      result = nil
      expect do
        result = controller.send(:ensure_social_photo_public!, habitation)
      end.to have_enqueued_job(Storage::PrepareSocialImageJob).with(
        11,
        13,
        tenant_id: 7,
        transformations: { resize_to_limit: [1200, 1200] }
      ).on_queue("media")

      expect(result).to eq(ready: true, url: "https://cdn.example.com/foto-original.png")
      expect(Storage::PublicPropertyPhoto).to have_received(:publish_attachment!).with(attachment)
    end

    it "marks the social photo as pending when neither variant nor original is public yet" do
      habitation = instance_double(Habitation, id: 11, tenant_id: 7)
      attachment = instance_double(ActiveStorage::Attachment, id: 13)
      blob = instance_double(ActiveStorage::Blob, image?: true)
      variant_image = double("variant image", attached?: false)
      variant = double("variant", image: variant_image)

      allow(habitation).to receive(:primary_image_source).and_return({ attachment: attachment })
      allow(attachment).to receive(:blob).and_return(blob)
      allow(blob).to receive(:variant).with(resize_to_limit: [1200, 1200]).and_return(variant)
      allow(Storage::PublicPropertyPhoto).to receive(:publish_attachment!).with(attachment)
      allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_attachment).with(attachment).and_return("https://cdn.example.com/foto-original.png")
      allow(controller).to receive(:social_image_url_accessible?).with("https://cdn.example.com/foto-original.png").and_return(false)

      result = nil
      expect do
        result = controller.send(:ensure_social_photo_public!, habitation)
      end.to have_enqueued_job(Storage::PrepareSocialImageJob).with(
        11,
        13,
        tenant_id: 7,
        transformations: { resize_to_limit: [1200, 1200] }
      ).on_queue("media")

      expect(result).to eq(ready: false, url: "https://cdn.example.com/foto-original.png")
    end

    it "reuses an existing social variant without enqueuing duplicate work" do
      tenant = instance_double(Tenant)
      habitation = instance_double(Habitation, id: 11, tenant_id: 7, tenant: tenant)
      attachment = instance_double(ActiveStorage::Attachment, id: 13)
      blob = instance_double(ActiveStorage::Blob, image?: true)
      variant_blob = instance_double(ActiveStorage::Blob)
      variant_image = double("variant image", attached?: true, blob: variant_blob)
      variant = double("variant", image: variant_image)

      allow(habitation).to receive(:primary_image_source).and_return({ attachment: attachment })
      allow(attachment).to receive(:blob).and_return(blob)
      allow(blob).to receive(:variant).with(resize_to_limit: [1200, 1200]).and_return(variant)
      allow(Storage::PublicPropertyPhoto).to receive(:publish_attachment!).with(attachment)
      allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!).with(variant_blob, raise_errors: true)
      allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(variant_blob, tenant: tenant).and_return("https://cdn.example.com/foto-social.png")
      allow(controller).to receive(:social_image_url_accessible?).with("https://cdn.example.com/foto-social.png").and_return(true)

      result = nil
      expect do
        result = controller.send(:ensure_social_photo_public!, habitation)
      end.not_to have_enqueued_job(Storage::PrepareSocialImageJob)

      expect(result).to eq(ready: true, url: "https://cdn.example.com/foto-social.png")
      expect(Storage::PublicPropertyPhoto).to have_received(:publish_blob!).with(variant_blob, raise_errors: true)
    end
  end
end
