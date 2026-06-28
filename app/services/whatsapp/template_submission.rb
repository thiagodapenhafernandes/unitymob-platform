module Whatsapp
  class TemplateSubmission
    def self.call(template:, client: Whatsapp::CloudClient.new)
      new(template:, client:).call
    end

    def initialize(template:, client:)
      @template = template
      @client = client
    end

    def call
      return validation_failure unless @template.valid?
      media = ensure_header_media_handle
      return media unless media[:ok]
      carousel_media = ensure_carousel_media_handles
      return carousel_media unless carousel_media[:ok]

      @template.assign_components_from_payload!
      result = @client.create_template(@template.meta_create_payload)
      return persist_success(result) if result[:ok]

      @template.submission_error = result[:error].presence || "Não foi possível enviar o modelo para aprovação."
      @template.errors.add(:base, @template.submission_error)
      log_submission_failure(result)
      { ok: false, error: @template.submission_error, template: @template }
    rescue ArgumentError => e
      @template.errors.add(:base, e.message)
      { ok: false, error: e.message, template: @template }
    end

    private

    def ensure_header_media_handle
      return { ok: true } unless @template.header_format.in?(%w[image video document])
      return { ok: true } if @template.header_media_handle.present?

      upload = Whatsapp::TemplateMediaHandleUploader.call(template: @template, client: @client)
      if upload[:ok]
        @template.header_media_handle = upload[:handle]
        return { ok: true }
      end

      @template.errors.add(:header_media_file, upload[:error])
      { ok: false, error: upload[:error], template: @template }
    end

    def ensure_carousel_media_handles
      return { ok: true } unless @template.template_type == "carousel"

      cards = @template.clean_carousel_cards
      attachables = carousel_attachables
      cards.each_with_index do |card, index|
        next if card["media_handle"].present?

        upload = Whatsapp::TemplateMediaHandleUploader.upload_attachable(
          attachable: attachables[index],
          media_type: card["media_type"],
          client: @client
        )
        unless upload[:ok]
          @template.errors.add(:carousel_cards, "card #{index + 1}: #{upload[:error]}")
          return { ok: false, error: upload[:error], template: @template }
        end

        card["media_handle"] = upload[:handle]
      end
      @template.carousel_cards = cards
      { ok: true }
    end

    def carousel_attachables
      change = @template.attachment_changes["carousel_card_media_files"]
      return change.attachables if change&.respond_to?(:attachables)

      @template.carousel_card_media_files.attachments.map(&:blob)
    end

    def persist_success(result)
      @template.status = result.dig(:data, "status").presence || "PENDING"
      @template.meta_id = result.dig(:data, "id").presence || @template.meta_id
      @template.submission_error = nil
      @template.save!
      { ok: true, template: @template, result: result }
    end

    def validation_failure
      { ok: false, error: @template.errors.full_messages.to_sentence, template: @template }
    end

    def log_submission_failure(result)
      Rails.logger.warn(
        "[Whatsapp::TemplateSubmission] falha ao enviar template para Meta " \
        "template=#{@template.name.inspect} status=#{result[:status].inspect} " \
        "meta_error=#{result[:meta_error].inspect} error=#{result[:error].to_s.truncate(240).inspect}"
      )
    end
  end
end
