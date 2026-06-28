module Whatsapp
  class CampaignAudienceResolver
    Result = Struct.new(
      :mode,
      :summary,
      :total,
      :valid_phone_count,
      :without_phone_count,
      :invalid_count,
      :sample,
      :errors,
      :scope,
      :leads,
      :recipients,
      keyword_init: true
    ) do
      def ok?
        errors.blank?
      end

      def leads_with_phone
        return leads if leads.present?

        scope.where.not(phone: [nil, ""])
      end

      def recipients_with_phone
        return recipients if recipients.present?

        leads_with_phone
      end
    end

    def self.call(campaign, materialize: false, uploaded_file: nil)
      new(campaign, materialize:, uploaded_file:).call
    end

    def initialize(campaign, materialize:, uploaded_file:)
      @campaign = campaign
      @materialize = materialize
      @uploaded_file = uploaded_file
    end

    def call
      return error_result("Salve a campanha antes de preparar destinatários.") if materialize && !campaign.persisted?

      case campaign.audience_mode
      when "spreadsheet"
        spreadsheet_result
      when "saved_audience"
        error_result("Público salvo ainda não foi configurado para esta campanha.")
      else
        filters_result
      end
    end

    private

    attr_reader :campaign, :materialize, :uploaded_file

    def filters_result
      filter_result = Whatsapp::CampaignFilterConditions.call(
        definition: campaign.audience_definition,
        legacy_filters: campaign.audience_filters
      )
      scoped = filter_result.scope
      valid = scoped.where.not(phone: [nil, ""])
      recipients = materialize ? materialize_filter_recipients(valid) : []

      Result.new(
        mode: "filters",
        summary: filter_result.summary,
        total: scoped.count,
        valid_phone_count: valid.count,
        without_phone_count: scoped.where(phone: [nil, ""]).count,
        invalid_count: 0,
        sample: valid.includes(:admin_user).order(created_at: :desc).limit(4).to_a,
        errors: [],
        scope: valid,
        leads: materialize ? [] : [],
        recipients:
      )
    end

    def spreadsheet_result
      import = Whatsapp::CampaignSpreadsheetImporter.call(campaign:, materialize:, uploaded_file:)
      return error_result(import.errors.to_sentence) if import.errors.present?

      if materialize && campaign.persisted?
        campaign.update_columns(
          import_status: "completed",
          import_total_rows: import.total,
          import_valid_rows: import.valid_phone_count,
          import_invalid_rows: import.invalid_rows.size,
          import_last_error: nil,
          updated_at: Time.current
        )
      end

      Result.new(
        mode: "spreadsheet",
        summary: "Planilha CSV · #{import.valid_phone_count} destinatários válidos · #{import.invalid_rows.size} linha(s) ignorada(s)",
        total: import.total,
        valid_phone_count: import.valid_phone_count,
        without_phone_count: import.without_phone_count,
        invalid_count: import.invalid_rows.size,
        sample: import.valid_rows.first(4),
        errors: [],
        scope: Lead.none,
        leads: [],
        recipients: materialize ? import.recipients : []
      )
    end

    def error_result(message)
      Result.new(
        mode: campaign.audience_mode,
        summary: message,
        total: 0,
        valid_phone_count: 0,
        without_phone_count: 0,
        invalid_count: 0,
        sample: [],
        errors: [message],
        scope: Lead.none,
        leads: [],
        recipients: []
      )
    end

    def materialize_filter_recipients(scope)
      existing_by_lead_id = campaign.campaign_recipients.where.not(lead_id: nil).index_by(&:lead_id)
      recipients = []

      scope.includes(:admin_user).find_each do |lead|
        recipient = existing_by_lead_id[lead.id] || campaign.campaign_recipients.find_or_initialize_by(lead: lead)
        recipient.assign_attributes(
          source: "filters",
          name: lead.display_name,
          phone_number: lead.display_phone,
          email: lead.display_email,
          origin: lead.origin,
          status: lead.status,
          tags: lead.tag_list,
          admin_user_id: lead.admin_user_id
        )
        recipient.save!
        recipients << recipient
      end

      recipients
    end
  end
end
