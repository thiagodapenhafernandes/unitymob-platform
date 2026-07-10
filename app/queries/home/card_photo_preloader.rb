module Home
  class CardPhotoPreloader
    ATTACHMENT_NAME = "photos".freeze
    CANDIDATE_MULTIPLIER = 2

    def initialize(records, limit:)
      @records = Array(records)
      @limit = limit.to_i
    end

    def call
      return records if records.empty? || limit <= 0

      attachments_by_record = candidate_attachments.group_by(&:record_id)
      records.each do |record|
        load_selected_attachments(record, attachments_by_record.fetch(record.id, []))
      end

      records
    end

    private

    attr_reader :records, :limit

    def candidate_attachments
      candidates = ranked_candidates.to_a
      missing_priority_ids = priority_attachment_ids - candidates.map(&:id)
      candidates.concat(attachments.where(id: missing_priority_ids).includes(:blob).to_a) if missing_priority_ids.any?
      candidates.uniq(&:id)
    end

    def ranked_candidates
      ranked = attachments.select(
        "active_storage_attachments.*",
        "ROW_NUMBER() OVER (PARTITION BY record_id ORDER BY id) AS card_rank"
      )

      ActiveStorage::Attachment
        .from("(#{ranked.to_sql}) active_storage_attachments")
        .where("card_rank <= ?", limit * CANDIDATE_MULTIPLIER)
        .includes(:blob)
    end

    def attachments
      ActiveStorage::Attachment.where(
        record_type: Habitation.polymorphic_name,
        record_id: records.map(&:id),
        name: ATTACHMENT_NAME
      )
    end

    def priority_attachment_ids
      @priority_attachment_ids ||= records.flat_map { |record| normalized_ids(record.photo_ids_order).first(limit) }.uniq
    end

    def load_selected_attachments(record, candidates)
      hidden_ids = normalized_ids(record.site_hidden_photo_ids)
      priority_ids = normalized_ids(record.photo_ids_order)
      priority_positions = priority_ids.each_with_index.to_h

      selected = candidates
        .reject { |attachment| hidden_ids.include?(attachment.id) }
        .sort_by { |attachment| [priority_positions.fetch(attachment.id, priority_ids.length), attachment.id] }
        .first(limit)

      association = record.association(:photos_attachments)
      association.target = selected
      association.loaded!
    end

    def normalized_ids(values)
      Array(values).filter_map { |value| Integer(value, exception: false) }.uniq
    end
  end
end
