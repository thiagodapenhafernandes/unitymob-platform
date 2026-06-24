module Habitations
  class MediaUpdater
    def self.strip_blank_photo_uploads!(attributes)
      return attributes unless attributes.key?(:photos)

      valid_photos = Array(attributes[:photos]).reject do |photo|
        blank_upload?(photo)
      end

      valid_photos.any? ? attributes[:photos] = valid_photos : attributes.delete(:photos)
      attributes
    end

    def self.blank_upload?(upload)
      upload.blank? || (upload.respond_to?(:size) && upload.size.to_i.zero?)
    end

    def initialize(habitation:, params:, actor:, request:, property_setting:)
      @habitation = habitation
      @params = params
      @actor = actor
      @request = request
      @property_setting = property_setting
    end

    def extract_photo_uploads!(attributes)
      Array(attributes.delete(:photos)).reject do |photo|
        self.class.blank_upload?(photo)
      end
    end

    def attach_new_photos(uploads, apply_watermark: apply_photo_watermark_requested?)
      valid_uploads = Array(uploads).reject do |photo|
        self.class.blank_upload?(photo)
      end
      return if valid_uploads.blank?

      existing_attachment_ids = habitation.photos.attachments.ids
      blobs = valid_uploads.map.with_index do |upload, index|
        Storage::BlobFactory.create_from_upload!(
          upload,
          service_name: Storage::Routing.service_name_for(record: habitation, name: "photos"),
          key_prefix: ["habitations", habitation.codigo.presence || habitation.id, "photos"].join("/"),
          metadata: {
            "identified" => true,
            "source" => "admin_upload",
            "position" => index + 1
          }
        )
      end
      habitation.photos.attach(blobs)
      habitation.reload

      new_attachment_ids = habitation.photos.attachments.ids - existing_attachment_ids
      return if new_attachment_ids.blank?

      habitation.photos.attachments.includes(:blob).where(id: new_attachment_ids).find_each do |attachment|
        Storage::PublicPropertyPhoto.publish_attachment!(attachment)
      end

      return unless apply_watermark && property_setting&.watermark_configured?

      HabitationPhotoWatermarkJob.perform_later(habitation.id, new_attachment_ids, property_setting.id)
    end

    def extract_document_uploads!(attributes)
      %i[fichas_cadastro autorizacoes_venda].each_with_object({}) do |key, result|
        next unless attributes.key?(key)

        uploads = Array(attributes.delete(key)).reject do |upload|
          self.class.blank_upload?(upload)
        end
        result[key] = uploads if uploads.any?
      end
    end

    def attach_new_documents(document_uploads)
      document_uploads.each do |name, uploads|
        valid_uploads = Array(uploads).reject do |upload|
          self.class.blank_upload?(upload)
        end
        next if valid_uploads.blank?

        blobs = valid_uploads.map do |upload|
          Storage::BlobFactory.create_from_upload!(
            upload,
            service_name: Storage::Routing.service_name_for(record: habitation, name: name),
            key_prefix: ["habitations", habitation.codigo.presence || habitation.id, name].join("/"),
            metadata: {
              "identified" => true,
              "source" => "admin_upload",
              "privacy" => "private"
            }
          )
        end
        habitation.public_send(name).attach(blobs)
      end
    end

    def apply_picture_removals_to_memory(indices = selected_picture_indices_for_removal)
      return if indices.blank?
      return unless habitation.pictures.is_a?(Array)

      indices = Array(indices).map(&:to_i).uniq
      habitation.pictures = habitation.pictures.each_with_index.filter_map do |picture, index|
        picture unless indices.include?(index)
      end
    end

    def apply_saved_photo_removals(attachment_ids = selected_photo_attachment_ids_for_removal)
      attachment_ids = Array(attachment_ids).map(&:to_i).uniq
      return if attachment_ids.blank?

      attachments = habitation.photos.attachments.includes(:blob).where(id: attachment_ids).to_a
      removed_ids = attachments.map(&:id)
      return if removed_ids.blank?

      attachments.each do |attachment|
        attachment_payload = AuditChangeRecorder.attachment_payload(attachment)
        record_habitation_attachment_removed(association: "photos", attachment_payload: attachment_payload)
        attachment.purge_later
      end

      remaining_order = Array(habitation.photo_ids_order).map(&:to_i) - removed_ids
      remaining_hidden_ids = Array(habitation.site_hidden_photo_ids).map(&:to_i) - removed_ids
      habitation.update_columns(photo_ids_order: remaining_order, site_hidden_photo_ids: remaining_hidden_ids)
    end

    def selected_photo_attachment_ids_for_removal
      comma_list_param(:remove_photo_ids).filter_map do |raw_id|
        raw_id if raw_id.match?(/\A\d+\z/)
      end.map(&:to_i).uniq
    end

    def selected_picture_indices_for_removal
      comma_list_param(:remove_picture_indices).filter_map do |raw_index|
        raw_index if raw_index.match?(/\A\d+\z/)
      end.map(&:to_i).uniq
    end

    def media_removal_requested?
      selected_photo_attachment_ids_for_removal.any? || selected_picture_indices_for_removal.any?
    end

    def apply_photo_watermark_requested?
      ActiveModel::Type::Boolean.new.cast(params.dig(:habitation, :apply_photo_watermark))
    end

    def touch_manual_habitation_update!(force: false)
      habitation.data_atualizacao_crm = Time.current if force || habitation.changed?
    end

    def record_habitation_updated(before_snapshot: nil)
      AuditChangeRecorder.new(
        habitation,
        actor: actor,
        request: request,
        source: habitation_audit_source,
        before_snapshot: before_snapshot,
        ignored_fields: AuditChangeRecorder::ADMIN_NOISE_FIELDS
      ).record_update!
    end

    private

    attr_reader :habitation, :params, :actor, :request, :property_setting

    def comma_list_param(key)
      raw_value = params.dig(:habitation, key)

      Array(raw_value).flat_map { |entry| entry.to_s.split(",") }
        .map(&:strip)
        .reject(&:blank?)
    end

    def record_habitation_attachment_removed(association:, attachment_payload:)
      AuditChangeRecorder.new(
        habitation,
        actor: actor,
        request: request,
        source: habitation_audit_source
      ).record_attachment_removed!(
        association: association,
        attachment_payload: attachment_payload
      )
    end

    def habitation_audit_source
      habitation&.broker_intake? ? "captacao" : "admin"
    end
  end
end
