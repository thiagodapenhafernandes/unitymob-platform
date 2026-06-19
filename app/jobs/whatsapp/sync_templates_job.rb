module Whatsapp
  class SyncTemplatesJob < ApplicationJob
    queue_as :default

    def perform
      result = Whatsapp::CloudClient.new.fetch_templates
      return { ok: false, error: result[:error] } unless result[:ok]

      synced = 0
      Array(result.dig(:data, "data")).each do |tpl|
        record = WhatsappTemplate.find_or_initialize_by(name: tpl["name"], language: tpl["language"].presence || "pt_BR")
        record.assign_attributes(
          category: tpl["category"],
          status: tpl["status"],
          meta_id: tpl["id"],
          body: body_text(tpl)
        )
        record.save!
        synced += 1
      end
      { ok: true, synced: synced }
    end

    private

    def body_text(tpl)
      component = Array(tpl["components"]).find { |c| c["type"].to_s.upcase == "BODY" }
      component && component["text"]
    end
  end
end
