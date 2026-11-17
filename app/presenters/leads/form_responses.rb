module Leads
  class FormResponses
    CONTACT_LABELS = { "full_name" => "Nome completo", "phone_number" => "Telefone", "email" => "E-mail", "city" => "Cidade" }.freeze

    def initialize(lead)
      @lead = lead
    end

    def groups
      history = @lead.activities.where(kind: "inquiry_complemented").order(:created_at, :id).flat_map do |activity|
        data = activity.metadata.to_h
        build_groups(data["inquiry_information"].to_h, data["inquiry_answers"], activity.created_at)
      end
      original = build_groups(@lead.other_information.to_h, @lead.custom_answers, @lead.created_at, @lead.product)
      (history + original).uniq { |group| [group[:provider], group[:event_id].presence || [group[:form_name], group[:received_at], group[:answers]]] }
        .sort_by { |group| group[:received_at] }.reverse
    end

    private

    def build_groups(info, answers, received_at, form_name = nil)
      groups = []
      if info["meta_leadgen_id"].present? || info["meta_form_id"].present?
        fields = info["field_data"].presence || answers
        groups << { provider: "Meta", event_id: info["meta_leadgen_id"],
          form_name: info["meta_form_name"].presence || form_name,
          received_at: received_at, answers: normalize_answers(fields, meta: true) }
      end
      { "linkedin" => "LinkedIn", "tiktok" => "TikTok" }.each do |key, provider|
        next unless info["#{key}_answers"].present?

        groups << { provider: provider, event_id: info["#{key}_response_id"] || info["#{key}_lead_id"],
          form_name: info["#{key}_form_name"], received_at: received_at,
          answers: normalize_answers(info["#{key}_answers"]) }
      end
      groups.reject { |group| group[:answers].empty? }
    end

    def normalize_answers(fields, meta: false)
      fields = fields.map { |key, answer| { "key" => key, "answer" => answer } } if fields.is_a?(Hash)
      Array(fields).filter_map do |field|
        next unless field.is_a?(Hash)

        field = field.stringify_keys
        question = (field["name"] || field["key"]).to_s
        next if question.blank?

        value = field.key?("values") ? field["values"] : field["answer"]
        values = Array(value).map(&:to_s)
        values = values.map { |text| text.match?(/\A[[:lower:]\d]+(?:_[[:lower:]\d]+)+\z/) ? text.humanize : text } if meta
        label = CONTACT_LABELS[question] || (question.include?("_") ? question.humanize : question)
        { question: label, answer: values.join("\n") }
      end
    end
  end
end
