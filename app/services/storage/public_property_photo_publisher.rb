module Storage
  class PublicPropertyPhotoPublisher
    CACHE_KEY = "storage:public_property_photo_publish:last_result".freeze
    PROGRESS_KEY = "storage:public_property_photo_publish:progress".freeze
    BATCH_SIZE = 200
    DEFAULT_CONCURRENCY = 12
    PROGRESS_INTERVAL = 100

    Result = Struct.new(:total, :published, :failed, :skipped, :errors, keyword_init: true) do
      def ok?
        failed.to_i.zero?
      end
    end

    Stats = Struct.new(:total_attachments, :total_blobs, keyword_init: true)
    LookupResult = Struct.new(:term, :habitations, :rows, keyword_init: true)
    LookupRow = Struct.new(:habitation, :attachment, :blob, :source_label, :public_url, keyword_init: true)
    PendingSummary = Struct.new(:total_habitations, :total_attachments, :sample, keyword_init: true)
    PendingProperty = Struct.new(:habitation, :attachments_count, keyword_init: true)

    def self.stats
      new.stats
    end

    def self.lookup(term)
      new.lookup(term)
    end

    def self.pending_summary(limit: 12)
      new.pending_summary(limit:)
    end

    def self.last_result
      Rails.cache.read(CACHE_KEY)
    end

    def self.progress
      Rails.cache.read(PROGRESS_KEY) || default_progress
    end

    def self.write_progress(attributes = {})
      payload = progress.merge(attributes.symbolize_keys)
      total = payload[:total].to_i
      processed = payload[:processed].to_i
      payload[:percent] = total.positive? ? ((processed.to_f / total) * 100).round(1) : 0
      payload[:percent] = 100.0 if payload[:status] == "completed"
      payload[:updated_at] = Time.current

      Rails.cache.write(PROGRESS_KEY, payload, expires_in: 12.hours)
      payload
    end

    def self.default_progress
      {
        status: "idle",
        total: 0,
        processed: 0,
        published: 0,
        failed: 0,
        skipped: 0,
        percent: 0,
        message: "Nenhuma publicação em andamento.",
        started_at: nil,
        finished_at: nil,
        updated_at: nil
      }
    end

    def self.write_last_result(result)
      Rails.cache.write(
        CACHE_KEY,
        {
          status: result.ok? ? "success" : "failed",
          message: result_message(result),
          finished_at: Time.current
        },
        expires_in: 7.days
      )
    end

    def self.result_message(result)
      [
        "#{result.published} publicadas",
        "#{result.skipped} ignoradas",
        "#{result.failed} falharam",
        "#{result.total} analisadas"
      ].join(", ")
    end

    def stats
      scope = eligible_attachments

      Stats.new(
        total_attachments: scope.count,
        total_blobs: scope.distinct.count(:blob_id)
      )
    end

    def lookup(term)
      normalized_term = term.to_s.strip
      return LookupResult.new(term: normalized_term, habitations: [], rows: []) if normalized_term.blank?

      habitations = lookup_habitations(normalized_term).to_a
      return LookupResult.new(term: normalized_term, habitations: [], rows: []) if habitations.empty?

      attachments = lookup_attachments_for(habitations).includes(:blob).order(:record_type, :record_id, :id).to_a
      rows = attachments.map { |attachment| build_lookup_row(attachment, habitations) }

      LookupResult.new(term: normalized_term, habitations: habitations, rows: rows)
    end

    def pending_summary(limit: 12)
      habitation_ids = candidate_habitation_ids
      sample_ids = habitation_ids.first(limit)
      habitations = Habitation.where(id: sample_ids).index_by(&:id)
      counts = attachment_counts_by_habitation(habitations.values)

      PendingSummary.new(
        total_habitations: habitation_ids.size,
        total_attachments: eligible_attachments.count,
        sample: sample_ids.filter_map do |id|
          habitation = habitations[id]
          next unless habitation

          PendingProperty.new(habitation:, attachments_count: counts.fetch(id, 0))
        end
      )
    end

    def publish_all(track_progress: false, concurrency: DEFAULT_CONCURRENCY, &progress_callback)
      result = build_result(total: eligible_attachments.count)
      write_progress_start(result.total) if track_progress

      if concurrency.to_i <= 1
        publish_all_sequentially(result, track_progress:, &progress_callback)
      else
        publish_all_concurrently(result, track_progress:, concurrency: concurrency.to_i, &progress_callback)
      end

      self.class.write_last_result(result)
      write_progress_finish(result) if track_progress
      progress_callback&.call(progress_payload(result.total, result, "completed"))
      result
    end

    def publish_attachment_id(attachment_id)
      attachment = ActiveStorage::Attachment.includes(:blob).find_by(id: attachment_id)
      return failed_result("Attachment #{attachment_id} não encontrado.") unless attachment

      result = build_result(total: 1)
      publish_attachment_object(attachment, result)
      self.class.write_last_result(result)
      result
    end

    def publish_habitation_id(habitation_id)
      habitation = Habitation.find_by(id: habitation_id)
      return failed_result("Imóvel #{habitation_id} não encontrado.") unless habitation

      attachments = lookup_attachments_for([habitation]).includes(:blob)
      result = build_result(total: attachments.count)

      attachments.find_each(batch_size: BATCH_SIZE) do |attachment|
        publish_attachment_object(attachment, result, trusted: true)
      end

      self.class.write_last_result(result)
      result
    end

    def publish_blob_id(blob_id)
      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return failed_result("Blob #{blob_id} não encontrado.") unless blob
      return failed_result("Blob #{blob_id} não está vinculado a foto pública de imóvel.") unless eligible_attachments.where(blob_id: blob.id).exists?

      result = build_result(total: 1)
      publish_blob_object(blob, result)
      self.class.write_last_result(result)
      result
    end

    private

    def eligible_attachments
      ActiveStorage::Attachment.where(record_type: "Habitation", name: "photos")
    end

    def candidate_habitation_ids
      eligible_attachments
        .distinct
        .pluck(:record_id)
    end

    def attachment_counts_by_habitation(habitations)
      return {} if habitations.blank?

      counts = Hash.new(0)

      lookup_attachments_for(habitations).find_each(batch_size: BATCH_SIZE) do |attachment|
        counts[attachment.record_id] += 1
      end

      counts
    end

    def lookup_habitations(term)
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      scope = Habitation.where("codigo = :term OR titulo_anuncio ILIKE :pattern", term: term, pattern: pattern)
      scope = scope.or(Habitation.where(id: term.to_i)) if term.match?(/\A\d+\z/)
      scope.order(updated_at: :desc).limit(8)
    end

    def lookup_attachments_for(habitations)
      habitation_ids = habitations.map(&:id)

      eligible_attachments.where(record_id: habitation_ids)
    end

    def build_lookup_row(attachment, habitations)
      habitation = habitations.find { |item| item.id == attachment.record_id }

      LookupRow.new(
        habitation: habitation,
        attachment: attachment,
        blob: attachment.blob,
        source_label: "Foto do imóvel",
        public_url: public_url_for(attachment)
      )
    end

    def public_url_for(attachment)
      Storage::PublicPropertyPhoto.public_url_for_attachment(attachment)
    rescue StandardError
      nil
    end

    def build_result(total:)
      Result.new(total: total, published: 0, failed: 0, skipped: 0, errors: [])
    end

    def failed_result(message)
      Result.new(total: 1, published: 0, failed: 1, skipped: 0, errors: [message])
    end

    def publish_all_sequentially(result, track_progress:, &progress_callback)
      eligible_attachments.includes(:blob).find_each(batch_size: BATCH_SIZE).with_index(1) do |attachment, index|
        publish_trusted_attachment_object(attachment, result)
        emit_progress(index, result, track_progress:, &progress_callback) if progress_due?(index)
      end
    end

    def publish_all_concurrently(result, track_progress:, concurrency:, &progress_callback)
      queue = Queue.new
      mutex = Mutex.new
      processed = 0
      worker_count = concurrency.clamp(1, 16)

      workers = worker_count.times.map do
        Thread.new do
          loop do
            attachment = queue.pop
            break if attachment.nil?

            status, error = publish_trusted_attachment_status(attachment)

            mutex.synchronize do
              apply_publish_status(result, status, error)
              processed += 1
              emit_progress(processed, result, track_progress:, &progress_callback) if progress_due?(processed)
            end
          end
        end
      end

      eligible_attachments.includes(:blob).find_each(batch_size: BATCH_SIZE) do |attachment|
        queue << attachment
      end

      worker_count.times { queue << nil }
      workers.each(&:join)
    end

    def progress_due?(processed)
      (processed % PROGRESS_INTERVAL).zero?
    end

    def emit_progress(processed, result, track_progress:)
      write_progress_step(processed, result) if track_progress
      yield progress_payload(processed, result, "running") if block_given?
    end

    def progress_payload(processed, result, status)
      {
        status: status,
        processed: processed,
        total: result.total,
        published: result.published,
        failed: result.failed,
        skipped: result.skipped,
        percent: result.total.to_i.positive? ? ((processed.to_f / result.total) * 100).round(1) : 0
      }
    end

    def write_progress_start(total)
      self.class.write_progress(
        status: "running",
        total: total,
        processed: 0,
        published: 0,
        failed: 0,
        skipped: 0,
        percent: 0,
        message: "Publicação das fotos públicas iniciada.",
        started_at: Time.current,
        finished_at: nil
      )
    end

    def write_progress_step(processed, result)
      self.class.write_progress(
        status: "running",
        processed: processed,
        published: result.published,
        failed: result.failed,
        skipped: result.skipped,
        message: "#{processed} de #{result.total} fotos analisadas."
      )
    end

    def write_progress_finish(result)
      self.class.write_progress(
        status: "completed",
        processed: result.total,
        published: result.published,
        failed: result.failed,
        skipped: result.skipped,
        message: self.class.result_message(result),
        finished_at: Time.current
      )
    end

    def publish_attachment_object(attachment, result, trusted: false)
      unless trusted || eligible_attachments.where(id: attachment.id).exists?
        result.skipped += 1
        result.errors << "Attachment #{attachment.id} ignorado: não é foto pública de imóvel."
        return
      end

      if Storage::PublicPropertyPhoto.publish_attachment!(attachment)
        result.published += 1
      else
        result.failed += 1
        result.errors << "Attachment #{attachment.id} falhou ao publicar."
      end
    rescue StandardError => e
      result.failed += 1
      result.errors << "Attachment #{attachment&.id}: #{e.class} - #{e.message}"
    end

    def publish_trusted_attachment_object(attachment, result)
      status, error = publish_trusted_attachment_status(attachment)
      apply_publish_status(result, status, error)
    end

    def publish_trusted_attachment_status(attachment)
      if Storage::PublicPropertyPhoto.publish_blob!(attachment.blob, raise_errors: true)
        [:published, nil]
      else
        [:failed, "Attachment #{attachment.id} falhou ao publicar."]
      end
    rescue StandardError => e
      [:failed, "Attachment #{attachment&.id}: #{e.class} - #{e.message}"]
    end

    def apply_publish_status(result, status, error = nil)
      case status
      when :published
        result.published += 1
      when :skipped
        result.skipped += 1
      else
        result.failed += 1
      end

      result.errors << error if error.present?
    end

    def publish_blob_object(blob, result)
      if Storage::PublicPropertyPhoto.publish_blob!(blob, raise_errors: true)
        result.published += 1
      else
        result.failed += 1
        result.errors << "Blob #{blob.id} falhou ao publicar."
      end
    rescue StandardError => e
      result.failed += 1
      result.errors << "Blob #{blob&.id}: #{e.class} - #{e.message}"
    end
  end
end
