module Storage
  class ProtectedBlobPolicy
    PROTECTED_ATTACHMENTS = {
      "PropertySetting" => %w[watermark_image],
      "LayoutSetting" => %w[logo favicon],
      "HomeSetting" => %w[hero_background_desktop hero_background_mobile],
      "HomeHeroSlide" => %w[image],
      "Banner" => %w[image_desktop image_mobile],
      "SeoSetting" => %w[og_image_file]
    }.freeze

    def self.protected_attachment?(attachment)
      new.protected_attachment?(attachment)
    end

    def self.protected_blob?(blob)
      new.protected_blob?(blob)
    end

    def self.protected_attachments_for(blob)
      new.protected_attachments_for(blob)
    end

    def self.critical_attachment_scope
      attachment_table = ActiveStorage::Attachment.arel_table
      predicates = PROTECTED_ATTACHMENTS.map do |record_type, names|
        attachment_table[:record_type].eq(record_type).and(attachment_table[:name].in(names))
      end

      return ActiveStorage::Attachment.none if predicates.blank?

      predicate = predicates.reduce { |left, right| left.or(right) }
      ActiveStorage::Attachment.includes(:blob).where(predicate)
    end

    def protected_attachment?(attachment)
      return false if attachment.blank?

      PROTECTED_ATTACHMENTS.fetch(attachment.record_type.to_s, []).include?(attachment.name.to_s)
    end

    def protected_blob?(blob)
      protected_attachments_for(blob).any?
    end

    def protected_attachments_for(blob)
      return [] if blob.blank?

      blob.attachments.select { |attachment| protected_attachment?(attachment) }
    end
  end
end
