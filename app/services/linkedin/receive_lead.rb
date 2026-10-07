module Linkedin
  class ReceiveLead
    def self.call(integration, response, client: Client.new(integration.access_token))
      new(integration, response, client).call
    end

    def initialize(integration, response, client)
      @integration, @response, @client = integration, response, client
    end

    def call
      return if @response["testLead"] || @response["leadType"] != "SPONSORED"
      account_id = Client.id(@response.dig("owner", "sponsoredAccount"))
      raise Client::Error, "Resposta recebida de uma conta de anúncios não selecionada." unless @integration.selected_account_ids.include?(account_id)
      response_id = @response.fetch("id")
      return if LinkedinLeadReceipt.where(tenant: @integration.tenant, response_id: response_id).exists?

      form_id = @response.fetch("versionedLeadGenFormUrn").match(/urn:li:leadGenForm:(\d+)/)&.[](1)
      raise Client::Error, "O LinkedIn não identificou o formulário do lead." unless form_id
      form = @client.form(form_id)
      unless Client.id(form.dig("owner", "sponsoredAccount")) == account_id
        raise Client::Error, "O formulário recebido não pertence à conta de anúncios selecionada."
      end
      answers = Array(@response.dig("formResponse", "answers")).index_by { |answer| answer["questionId"].to_s }
      fields = {}
      responses = {}
      Array(form.dig("content", "questions")).each do |question|
        answer = answers[question["questionId"].to_s]
        next unless answer
        value = answer.dig("answerDetails", "textQuestionAnswer", "answer")
        choices = answer.dig("answerDetails", "multipleChoiceAnswer", "options")
        if choices
          options = Array(question.dig("questionDetails", "multipleChoiceQuestionDetails", "options")).index_by { |option| option["id"].to_s }
          value = choices.map { |id| localized(options[id.to_s]&.dig("text")) || id.to_s }.join(", ")
        end
        label = localized(question["question"]) || question["name"] || question["questionId"].to_s
        responses[label] = value
        fields[question["predefinedField"]] = value if question["predefinedField"].present?
      end
      name = [fields["FIRST_NAME"], fields["LAST_NAME"]].compact_blank.join(" ").presence || "Lead LinkedIn"
      phone = fields["PHONE_NUMBER"].presence || fields["MOBILE_PHONE_NUMBER"].presence || fields["WORK_PHONE_NUMBER"].presence
      email = fields["EMAIL"].presence || fields["EMAIL_ADDRESS"].presence || fields["WORK_EMAIL"].presence
      raise Client::Error, "Um formulário do LinkedIn não forneceu telefone nem e-mail. Revise os campos de contato." if phone.blank? && email.blank?

      campaign_id = Client.id(@response.dig("leadMetadata", "sponsoredLeadMetadata", "campaign"))
      campaign_name = @response.dig("leadMetadataInfo", "sponsoredLeadMetadataInfo", "campaign", "name") || @integration.catalog.dig(campaign_id, "name")
      Current.set(tenant: @integration.tenant) do
        LinkedinLeadReceipt.transaction(requires_new: true) do
          receipt = LinkedinLeadReceipt.create!(tenant: @integration.tenant, response_id: response_id)
          lead = Lead.create!(tenant: @integration.tenant, name: name, client_name: name, email: email, client_email: email, phone: phone, client_phone: phone,
            origin: "LinkedIn Ads", product: form["name"], attribution_channel: "linkedin_ads", attribution_source: "linkedin",
            attribution_data: { "version" => 2, "provider" => "linkedin_lead_sync", "campaign_name" => campaign_name, "campaign_id" => campaign_id, "form_id" => form_id },
            other_information: { "linkedin_response_id" => response_id, "linkedin_account_id" => account_id, "linkedin_campaign_id" => campaign_id,
              "linkedin_form_id" => form_id, "linkedin_form_name" => form["name"], "linkedin_answers" => responses,
              "linkedin_submitted_at" => @response["submittedAt"], "linkedin_form_response" => @response["formResponse"], "linkedin_consents" => @response.dig("formResponse", "consentResponses") })
          receipt.update!(lead: lead)
        end
      end
      @integration.update!(last_lead_received_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      nil # Unique tenant + response ID also covers concurrent deliveries and retries.
    end

    private

    def localized(value)
      return value if value.is_a?(String)
      value&.dig("localized")&.values&.first
    end
  end
end
