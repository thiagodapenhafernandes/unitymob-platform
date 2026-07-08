module Whatsapp
  class SyncTemplatesJob < ApplicationJob
    queue_as :default
    MAX_HEADER_MEDIA_DOWNLOAD_BYTES = 25.megabytes

    def perform(tenant_id = nil, sender_number_id: nil)
      # Recorrente (config/recurring.yml) roda sem args: fan-out para os
      # tenants com integração conectada; chamadas manuais passam tenant_id.
      return fan_out_all_tenants! if tenant_id.blank?

      tenant = Tenant.find_by(id: tenant_id)
      return { ok: false, error: "Tenant não encontrado." } unless tenant

      # Current.set restaura o valor anterior ao sair (o ensure antigo zerava
      # Current.tenant no resto do request após perform_now).
      Current.set(tenant: tenant) do
        sync_templates_for(tenant, sender_number_id: sender_number_id)
      end
    end

    private

    def fan_out_all_tenants!
      tenant_ids = WhatsappBusinessIntegration
                   .where(status: "connected")
                   .where.not(waba_id: [nil, ""])
                   .distinct
                   .pluck(:tenant_id)
                   .compact
      tenant_ids.each { |id| self.class.perform_later(id) }
      { ok: true, enqueued: tenant_ids.size }
    end

    def sync_templates_for(tenant, sender_number_id: nil)
      source = sync_source_for(tenant, sender_number_id)
      return { ok: false, error: "Selecione um número WhatsApp configurado." } unless source

      result = Whatsapp::CloudClient.new(source).fetch_templates
      return { ok: false, error: result[:error] } unless result[:ok]

      synced = 0
      Array(result.dig(:data, "data")).each do |tpl|
        record = tenant.whatsapp_templates.find_or_initialize_by(
          name: tpl["name"],
          language: tpl["language"].presence || "pt_BR",
          waba_id: source.waba_id
        )
        record.assign_attributes(
          category: normalized_category(tpl["category"]),
          status: tpl["status"].presence || "PENDING",
          meta_id: tpl["id"],
          body: body_text(tpl),
          components: Array(tpl["components"]),
          template_type: template_type(tpl),
          header_format: header_format(tpl),
          header_text: header_text(tpl),
          header_media_handle: header_media_handle(tpl),
          footer_text: footer_text(tpl),
          buttons: buttons(tpl),
          carousel_cards: carousel_cards(tpl),
          flow_config: flow_config(tpl)
        )
        record.save!
        attach_synced_header_media(record)
        synced += 1
      end
      { ok: true, synced: synced }
    end

    def sync_source_for(tenant, sender_number_id)
      sender = tenant.whatsapp_sender_numbers.active.find_by(id: sender_number_id) if sender_number_id.present?
      return sender if sender&.waba_id.present?

      integration = WhatsappBusinessIntegration.current(tenant)
      return integration if integration.messaging_ready? && integration.waba_id.present?

      nil
    end

    def attach_synced_header_media(record)
      return unless record.header_format.in?(%w[image video document])
      return if record.header_media_file.attached?

      url = record.header_media_handle.to_s
      return unless url.match?(%r{\Ahttps?://}i)

      response = HTTParty.get(url, timeout: 30)
      unless response.respond_to?(:success?) && response.success?
        Rails.logger.warn("[whatsapp templates sync] falha ao baixar midia do template=#{record.id} status=#{response.respond_to?(:code) ? response.code : "unknown"}")
        return
      end

      body = response.body.to_s
      if body.blank? || body.bytesize > MAX_HEADER_MEDIA_DOWNLOAD_BYTES
        Rails.logger.warn("[whatsapp templates sync] midia ignorada template=#{record.id} bytes=#{body.bytesize}")
        return
      end

      content_type = response.headers["content-type"].to_s.split(";").first.presence || content_type_for(record.header_format)
      record.header_media_file.attach(
        io: StringIO.new(body),
        filename: header_media_filename(url, record.header_format),
        content_type: content_type
      )
    rescue => e
      Rails.logger.warn("[whatsapp templates sync] nao foi possivel anexar midia do template=#{record.id}: #{e.class}: #{e.message}")
    end

    def body_text(tpl)
      component = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "BODY" }
      component && component["text"]
    end

    def footer_text(tpl)
      component = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "FOOTER" }
      component && component["text"]
    end

    def header_format(tpl)
      component = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "HEADER" }
      format = component&.fetch("format", nil).to_s.downcase.presence || "none"
      WhatsappTemplate::HEADER_FORMATS.key?(format) ? format : "none"
    end

    def header_text(tpl)
      component = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "HEADER" }
      component && component["format"].to_s.casecmp("TEXT").zero? ? component["text"].to_s : nil
    end

    def header_media_handle(tpl)
      component = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "HEADER" }
      return nil unless component && component["format"].to_s.downcase.in?(%w[image video document])

      Array(component.dig("example", "header_handle")).first.to_s.presence
    end

    def buttons(tpl)
      component = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "BUTTONS" }
      Array(component&.dig("buttons")).map do |button|
        type = button["type"].to_s.downcase
        {
          "kind" => type == "phone_number" ? "phone_number" : type,
          "text" => button["text"],
          "url" => button["url"],
          "phone_number" => button["phone_number"]
        }.compact_blank
      end
    end

    def template_type(tpl)
      components = Array(tpl["components"])
      return "carousel" if components.any? { |c| c["type"].to_s.upcase == "CAROUSEL" }
      return "flow" if components.any? { |c| Array(c["buttons"]).any? { |button| button["type"].to_s.upcase == "FLOW" } }

      "text"
    end

    def carousel_cards(tpl)
      carousel = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "CAROUSEL" }
      Array(carousel&.dig("cards")).map do |card|
        components = Array(card["components"])
        header = components.find { |component| component["type"].to_s.upcase == "HEADER" }
        body = components.find { |component| component["type"].to_s.upcase == "BODY" }
        buttons = components.find { |component| component["type"].to_s.upcase == "BUTTONS" }
        button = Array(buttons&.dig("buttons")).first

        {
          "media_type" => header&.dig("format").to_s.downcase.presence || "image",
          "media_handle" => Array(header&.dig("example", "header_handle")).first.to_s,
          "text" => body&.dig("text").to_s,
          "button_kind" => button_kind(button),
          "button_text" => button&.dig("text").to_s,
          "button_url" => button&.dig("url").to_s,
          "button_url_example" => Array(button&.dig("example")).first.to_s,
          "button_phone_number" => button&.dig("phone_number").to_s
        }.compact_blank
      end
    end

    def button_kind(button)
      type = button&.dig("type").to_s.downcase
      return "phone_number" if type == "phone_number"
      return "quick_reply" if type == "quick_reply"

      "url"
    end

    def flow_config(tpl)
      button = Array(Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "BUTTONS" }&.dig("buttons"))
               .find { |item| item["type"].to_s.upcase == "FLOW" }
      return {} if button.blank?

      {
        "flow_id" => button["flow_id"].to_s,
        "button_text" => button["text"].to_s,
        "action" => button["flow_action"].to_s.downcase.presence || "navigate",
        "screen" => button["navigate_screen"].to_s
      }.compact_blank
    end

    def normalized_category(category)
      value = category.to_s.upcase.presence || "MARKETING"
      WhatsappTemplate::CATEGORIES.include?(value) ? value : "MARKETING"
    end

    def header_media_filename(url, format)
      path = URI.parse(url).path.to_s
      basename = File.basename(path)
      return basename if basename.present? && basename.include?(".")

      "header_media#{extension_for(format)}"
    rescue URI::InvalidURIError
      "header_media#{extension_for(format)}"
    end

    def extension_for(format)
      {
        "image" => ".jpg",
        "video" => ".mp4",
        "document" => ".pdf"
      }.fetch(format.to_s, ".bin")
    end

    def content_type_for(format)
      {
        "image" => "image/jpeg",
        "video" => "video/mp4",
        "document" => "application/pdf"
      }.fetch(format.to_s, "application/octet-stream")
    end
  end
end
