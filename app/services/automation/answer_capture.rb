module Automation
  # Guarda a resposta do cliente como variável do fluxo ({{resposta.<variavel>}}) e, se configurado,
  # grava num campo do lead. Reaproveita os campos que o lead já tem: nome, e-mail e `custom_answers`
  # (a mesma lista de respostas dos formulários), sem coluna nova.
  class AnswerCapture
    ANSWER_TYPES = %w[text email phone number].freeze
    LEAD_TARGETS = %w[none name email custom].freeze
    MAX_LENGTH = 500

    Result = Struct.new(:variable, :value, :lead_field, :lead_written, :note, keyword_init: true)

    def self.slug(value)
      value.to_s.parameterize(separator: "_").first(40)
    end

    def self.validation_messages(config)
      config = (config || {}).with_indifferent_access
      errors = []
      errors << "tem guardar resposta sem nome da variavel" if slug(config[:variable]).blank?
      errors << "tem guardar resposta com tipo invalido" unless ANSWER_TYPES.include?(config[:answer_type].presence || "text")
      target = config[:lead_target].presence || "none"
      errors << "tem guardar resposta com campo do lead invalido" unless LEAD_TARGETS.include?(target)
      errors << "tem guardar resposta em campo personalizado sem nome" if target == "custom" && slug(config[:custom_key]).blank?
      errors << "tem guardar resposta de telefone ou numero gravando no nome do lead" if target == "name" && %w[phone number].include?(config[:answer_type].to_s)
      errors << "tem guardar resposta que nao e e-mail gravando no e-mail do lead" if target == "email" && config[:answer_type].to_s != "email"
      errors
    end

    def self.call(lead:, config:, response_body:)
      new(lead, config, response_body).call
    end

    def initialize(lead, config, response_body)
      @lead = lead
      @config = (config || {}).with_indifferent_access
      @value = normalize(response_body)
    end

    def call
      result = Result.new(variable: self.class.slug(@config[:variable]), value: @value, lead_field: @config[:lead_target].presence || "none", lead_written: false)
      return result.tap { |item| item.note = "resposta vazia" } if @value.blank? || @lead.nil?

      write_to_lead(result)
      result
    end

    private

    def normalize(raw)
      text = raw.to_s.squish.first(MAX_LENGTH)
      case @config[:answer_type].presence || "text"
      when "email" then text.downcase
      when "phone" then Phones::Normalizer.call(text).to_s
      when "number" then text.tr(",", ".")
      else text
      end
    end

    def write_to_lead(result)
      case result.lead_field
      when "name" then update_attribute!(result, :name)
      when "email" then update_attribute!(result, :email)
      when "custom" then upsert_custom_answer(result)
      end
    end

    def update_attribute!(result, attribute)
      previous = @lead.public_send(attribute)
      return result.note = "valor igual ao atual" if previous.to_s == @value

      if @lead.update(attribute => @value)
        result.lead_written = true
        log_activity(attribute.to_s, previous)
      else
        @lead.restore_attributes
        result.note = @lead.errors.full_messages.to_sentence.presence || "o lead recusou o valor"
      end
    end

    def upsert_custom_answer(result)
      key = self.class.slug(@config[:custom_key])
      answers = Array(@lead.custom_answers).map { |item| item.is_a?(Hash) ? item.deep_dup : {} }
      current = answers.find { |item| item["key"].to_s == key }
      previous = current&.dig("answer")
      entry = { "key" => key, "label" => @config[:custom_label].presence || key.humanize, "answer" => @value, "source" => "automation" }
      current ? current.merge!(entry) : answers << entry

      if @lead.update(custom_answers: answers)
        result.lead_written = true
        log_activity("custom_answers.#{key}", previous)
      else
        @lead.restore_attributes
        result.note = @lead.errors.full_messages.to_sentence.presence || "o lead recusou o valor"
      end
    end

    def log_activity(field, previous)
      LeadActivity.log!(lead: @lead, kind: "automation", metadata: { by: "Automação", action: "capture_answer", field: field, previous: previous, value: @value })
    end
  end
end
