module Whatsapp
  class SyncTemplatesJob < ApplicationJob
    queue_as :default

    def perform(tenant_id = nil)
      tenant = Tenant.find_by(id: tenant_id) if tenant_id.present?
      return { ok: false, error: "Tenant não encontrado." } unless tenant

      Current.tenant = tenant
      integration = WhatsappBusinessIntegration.current(tenant)
      result = Whatsapp::CloudClient.new(integration).fetch_templates
      return { ok: false, error: result[:error] } unless result[:ok]

      synced = 0
      Array(result.dig(:data, "data")).each do |tpl|
        record = tenant.whatsapp_templates.find_or_initialize_by(name: tpl["name"], language: tpl["language"].presence || "pt_BR")
        record.assign_attributes(
          category: normalized_category(tpl["category"]),
          status: tpl["status"].presence || "PENDING",
          meta_id: tpl["id"],
          body: body_text(tpl),
          components: Array(tpl["components"]),
          template_type: template_type(tpl),
          header_format: header_format(tpl),
          header_text: header_text(tpl),
          footer_text: footer_text(tpl),
          buttons: buttons(tpl),
          carousel_cards: carousel_cards(tpl),
          flow_config: flow_config(tpl)
        )
        record.save!
        synced += 1
      end
      { ok: true, synced: synced }
    ensure
      Current.tenant = nil if tenant_id.present?
    end

    private

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
  end
end
