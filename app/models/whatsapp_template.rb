class WhatsappTemplate < ApplicationRecord
  include TenantScoped

  TEMPLATE_TYPES = {
    "text" => "Mensagem de Texto",
    "carousel" => "Media Card Carousel",
    "flow" => "Template com Flow"
  }.freeze
  CATEGORIES = %w[MARKETING UTILITY AUTHENTICATION].freeze
  HEADER_FORMATS = {
    "none" => "Sem mídia",
    "text" => "Texto curto",
    "image" => "Imagem",
    "video" => "Vídeo",
    "document" => "Documento"
  }.freeze
  BUTTON_KINDS = {
    "quick_reply" => "Resposta rápida",
    "url" => "URL",
    "phone_number" => "Telefone"
  }.freeze
  CAROUSEL_MEDIA_TYPES = {
    "image" => "Imagem",
    "video" => "Vídeo"
  }.freeze
  FLOW_ACTIONS = {
    "navigate" => "Abrir tela do Flow",
    "data_exchange" => "Enviar dados para o Flow"
  }.freeze

  has_many :whatsapp_campaigns, dependent: :restrict_with_error
  has_many :notification_template_settings, dependent: :restrict_with_error
  has_one_attached :header_media_file
  has_many_attached :carousel_card_media_files

  validates :name, presence: true, uniqueness: { scope: [:tenant_id, :waba_id, :language] }
  validates :template_type, inclusion: { in: TEMPLATE_TYPES.keys }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :header_format, inclusion: { in: HEADER_FORMATS.keys }
  validate :validate_template_submission
  before_validation :normalize_meta_identifier
  before_validation :normalize_media_handles

  scope :approved, -> { where(status: "APPROVED") }
  scope :ordered, -> { order(:name) }
  scope :search, ->(query) { where("name ILIKE ?", "%#{sanitize_sql_like(query)}%") if query.present? }

  def approved? = status.to_s.upcase == "APPROVED"
  def pending? = status.to_s.upcase == "PENDING"

  def template_type_label
    TEMPLATE_TYPES.fetch(template_type.to_s, TEMPLATE_TYPES["text"])
  end

  def category_label
    category.to_s.titleize
  end

  # Substitui {{1}}, {{2}}... pelos valores informados (preview / envio simples).
  def render_body(values = [])
    text = body.to_s
    Array(values).each_with_index do |val, i|
      text = text.gsub("{{#{i + 1}}}", val.to_s)
    end
    text
  end

  def variable_count
    variable_references.map { |item| item[:index].to_i }.max || 0
  end

  def variable_references
    references = {}

    variable_reference_sources.each do |source|
      text = source[:text].to_s
      placeholders_in(text).each do |index|
        placeholder = "{{#{index}}}"
        references[index] ||= { index: index, placeholder: placeholder, contexts: [] }
        references[index][:contexts] << variable_context_for_source(source, placeholder)
      end
    end

    references.values.sort_by { |item| item[:index] }.map do |item|
      item.merge(context: item[:contexts].compact_blank.uniq.first || "Variável #{item[:placeholder]}")
    end
  end

  def body_variable_examples
    Array(example_values).map(&:to_s).reject(&:blank?).first(body_variable_count)
  end

  def interactive_buttons
    case template_type
    when "text"
      clean_buttons.each_with_index.map do |button, index|
        template_button_payload(
          key: "text:#{index}:#{button['text'].parameterize}",
          text: button["text"],
          kind: button["kind"],
          source: "template"
        )
      end
    when "carousel"
      clean_carousel_cards.each_with_index.map do |card, index|
        template_button_payload(
          key: "carousel:#{index}:#{card['button_text'].parameterize}",
          text: card["button_text"],
          kind: card["button_kind"],
          source: "carousel",
          context: "Card #{index + 1}"
        )
      end
    when "flow"
      config = clean_flow_config
      [
        template_button_payload(
          key: "flow:0:#{config['button_text'].parameterize}",
          text: config["button_text"],
          kind: "flow",
          source: "flow"
        )
      ].compact
    else
      []
    end.compact
  end

  def meta_create_payload
    {
      name: name.to_s.strip,
      language: language.presence || "pt_BR",
      category: category.presence || "MARKETING",
      allow_category_change: allow_category_change?,
      components: components_payload
    }.compact
  end

  def components_payload
    case template_type
    when "text"
      [header_component, body_component, footer_component, buttons_component].compact
    when "carousel"
      carousel_components_payload
    when "flow"
      flow_components_payload
    else
      raise ArgumentError, "Tipo de template inválido."
    end
  end

  def assign_components_from_payload!
    self.components = components_payload
  end

  def clean_buttons
    raw_buttons =
      if buttons.is_a?(Hash)
        buttons.sort_by { |key, _value| key.to_s }.map { |_key, value| value }
      else
        Array(buttons)
      end

    raw_buttons.filter_map do |button|
      attrs = button.respond_to?(:to_unsafe_h) ? button.to_unsafe_h : button.to_h
      kind = attrs["kind"].presence || attrs[:kind].presence
      text = attrs["text"].to_s.strip
      next if kind.blank? || text.blank?

      {
        "kind" => kind,
        "text" => text,
        "url" => attrs["url"].to_s.strip,
        "phone_number" => attrs["phone_number"].presence || attrs["url"].presence
      }.compact_blank
       .tap { |row| row["phone_number"] = normalize_template_phone(row["phone_number"]) if row["phone_number"].present? }
    end.first(3)
  end

  def clean_carousel_cards
    raw_cards =
      if carousel_cards.is_a?(Hash)
        carousel_cards.sort_by { |key, _value| key.to_s }.map { |_key, value| value }
      else
        Array(carousel_cards)
      end

    raw_cards.filter_map do |card|
      attrs = card.respond_to?(:to_unsafe_h) ? card.to_unsafe_h : card.to_h
      media_type = attrs["media_type"].presence || attrs[:media_type].presence || "image"
      text = attrs["text"].to_s.strip
      button_text = attrs["button_text"].to_s.strip
      button_kind = attrs["button_kind"].presence || attrs[:button_kind].presence || "url"
      button_url = attrs["button_url"].to_s.strip
      button_url_example = attrs["button_url_example"].to_s.strip
      button_phone_number = attrs["button_phone_number"].presence || attrs[:button_phone_number].presence
      handle = normalize_media_handle(attrs["media_handle"])
      next if text.blank? && button_text.blank? && button_url.blank? && button_phone_number.blank? && handle.blank?

      {
        "media_type" => CAROUSEL_MEDIA_TYPES.key?(media_type.to_s) ? media_type.to_s : "image",
        "media_handle" => handle,
        "text" => text,
        "button_kind" => BUTTON_KINDS.key?(button_kind.to_s) ? button_kind.to_s : "url",
        "button_text" => button_text,
        "button_url" => button_url,
        "button_url_example" => button_url_example,
        "button_phone_number" => normalize_template_phone(button_phone_number)
      }.compact_blank
    end.first(10)
  end

  def clean_flow_config
    attrs = flow_config.respond_to?(:to_unsafe_h) ? flow_config.to_unsafe_h : flow_config.to_h
    action = attrs["action"].presence || attrs[:action].presence || "navigate"
    {
      "flow_id" => attrs["flow_id"].to_s.strip,
      "button_text" => attrs["button_text"].to_s.strip.presence || "Abrir",
      "action" => FLOW_ACTIONS.key?(action.to_s) ? action.to_s : "navigate",
      "screen" => attrs["screen"].to_s.strip
    }.compact_blank
  end

  private

  def variable_reference_sources
    component_sources = sources_from_components
    return component_sources if component_sources.present?

    sources_from_template_fields
  end

  def sources_from_components
    Array(components).flat_map.with_index do |component, index|
      component_variable_sources(normalize_component(component), "Componente #{index + 1}")
    end
  end

  def component_variable_sources(component, fallback_label)
    case component["type"].to_s.upcase
    when "HEADER"
      [{ label: "Cabeçalho", text: component["text"] }]
    when "BODY"
      [{ label: "Corpo", text: component["text"] }]
    when "BUTTONS"
      Array(component["buttons"]).flat_map.with_index do |button, index|
        button_variable_sources(normalize_component(button), index, "Botão #{index + 1}")
      end
    when "CAROUSEL"
      Array(component["cards"]).flat_map.with_index do |card, card_index|
        card_components = Array(normalize_component(card)["components"])
        card_components.flat_map do |card_component|
          component_variable_sources(
            normalize_component(card_component),
            "Card #{card_index + 1}"
          ).map do |source|
            source.merge(label: ["Card #{card_index + 1}", source[:label]].compact_blank.join(" · "))
          end
        end
      end
    else
      [{ label: fallback_label, text: component["text"] }]
    end
  end

  def button_variable_sources(button, index, label)
    return [] unless button["type"].to_s.casecmp("URL").zero?

    [{ label: "#{label} · URL", text: button["url"] }]
  end

  def sources_from_template_fields
    sources = []
    sources << { label: "Cabeçalho", text: header_text } if header_format == "text"
    sources << { label: "Corpo", text: body }
    sources << { label: "Rodapé", text: footer_text }
    clean_buttons.each_with_index do |button, index|
      sources << { label: "Botão #{index + 1} · URL", text: button["url"] } if button["kind"] == "url"
    end
    clean_carousel_cards.each_with_index do |card, index|
      sources << { label: "Card #{index + 1} · Corpo", text: card["text"] }
      sources << { label: "Card #{index + 1} · Botão URL", text: card["button_url"] } if card["button_kind"] == "url"
    end
    sources
  end

  def variable_context_for_source(source, placeholder)
    text = source[:text].to_s
    context = template_variable_context(text, placeholder)
    label = source[:label].to_s
    return context if label.blank? || label == "Corpo"

    "#{label}: #{context}"
  end

  def placeholders_in(text)
    text.to_s.scan(/\{\{\s*(\d+)\s*\}\}/).flatten.map(&:to_i).uniq.sort
  end

  def body_variable_count
    placeholders_in(body).max || 0
  end

  def normalize_component(value)
    attrs = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
    attrs.deep_stringify_keys
  end

  def template_variable_context(text, placeholder)
    line = text.to_s.lines.find { |item| item.include?(placeholder) }.to_s.strip
    return "Variável #{placeholder}" if line.blank?
    return line unless line.scan(/\{\{\d+\}\}/).size > 1

    fragment_for_placeholder(line, placeholder).presence || line
  end

  def fragment_for_placeholder(line, placeholder)
    position = line.index(placeholder)
    return nil unless position

    start_index = [line.rindex(/[\.\!\?\n]/, position)&.+(1), previous_placeholder_end(line, position), 0].compact.max
    next_punctuation = line.index(/[\.\!\?]/, position + placeholder.length)
    next_placeholder = line.index(/\{\{\d+\}\}/, position + placeholder.length)
    end_index = [next_punctuation&.+(1), next_placeholder, line.length].compact.min

    line[start_index...end_index].to_s.strip.gsub(/\s+/, " ")
  end

  def previous_placeholder_end(line, position)
    previous = line[0...position].to_s.to_enum(:scan, /\{\{\d+\}\}/).map { Regexp.last_match.end(0) }.last
    return nil unless previous

    previous
  end

  def template_button_payload(key:, text:, kind:, source:, context: nil)
    label = text.to_s.strip
    return if label.blank?

    {
      "key" => key,
      "text" => label,
      "kind" => kind.to_s,
      "kind_label" => BUTTON_KINDS.fetch(kind.to_s, kind.to_s == "flow" ? "Flow" : kind.to_s.humanize),
      "source" => source,
      "context" => context,
      "actionable_reply" => kind.to_s.in?(%w[quick_reply flow])
    }.compact
  end

  def header_component
    return nil if header_format == "none"

    format = header_format.to_s.upcase
    component = { type: "HEADER", format: format }
    if format == "TEXT"
      component[:text] = header_text.to_s
    else
      component[:example] = { header_handle: [normalize_media_handle(header_media_handle)] } if header_media_handle.present?
    end
    component
  end

  def body_component
    component = { type: "BODY", text: body.to_s }
    examples = body_variable_examples
    component[:example] = { body_text: [examples] } if examples.present?
    component
  end

  def footer_component
    return nil if footer_text.blank?

    { type: "FOOTER", text: footer_text.to_s }
  end

  def buttons_component
    rows = clean_buttons.map do |button|
      case button["kind"]
      when "quick_reply"
        { type: "QUICK_REPLY", text: button["text"] }
      when "url"
        { type: "URL", text: button["text"], url: button["url"].to_s }
      when "phone_number"
        { type: "PHONE_NUMBER", text: button["text"], phone_number: button["phone_number"].to_s }
      end
    end.compact
    return nil if rows.blank?

    { type: "BUTTONS", buttons: rows }
  end

  def carousel_components_payload
    [
      body_component,
      {
        type: "CAROUSEL",
        cards: clean_carousel_cards.map do |card|
          {
            components: [
              {
                type: "HEADER",
                format: card["media_type"].to_s.upcase,
                example: { header_handle: [normalize_media_handle(card["media_handle"])] }
              },
              { type: "BODY", text: card["text"].to_s },
              {
                type: "BUTTONS",
                buttons: [
                  carousel_card_button(card)
                ]
              }
            ]
          }
        end
      }
    ]
  end

  def flow_components_payload
    config = clean_flow_config
    button = {
      type: "FLOW",
      text: config["button_text"].to_s,
      flow_id: config["flow_id"].to_s,
      flow_action: config["action"].to_s.upcase
    }
    button[:navigate_screen] = config["screen"].to_s if config["screen"].present? && config["action"] == "navigate"

    [body_component, footer_component, { type: "BUTTONS", buttons: [button] }].compact
  end

  def normalize_template_phone(value)
    normalized = Phones::Normalizer.call(value)
    normalized.present? ? "+#{normalized}" : ""
  end

  def validate_template_submission
    case template_type
    when "text"
      validate_text_template_submission
    when "carousel"
      validate_carousel_template_submission
    when "flow"
      validate_flow_template_submission
    end
  end

  def validate_text_template_submission

    errors.add(:body, "é obrigatório para aprovação") if body.blank?
    errors.add(:header_text, "é obrigatório quando o cabeçalho usa texto") if header_format == "text" && header_text.blank?
    if header_format.in?(%w[image video document]) && header_media_handle.blank? && !header_media_available?
      errors.add(:header_media_file, "é obrigatória quando o cabeçalho usa mídia")
    end

    clean_buttons.each do |button|
      errors.add(:buttons, "URL é obrigatória para botão de URL") if button["kind"] == "url" && button["url"].blank?
      errors.add(:buttons, "telefone é obrigatório para botão de telefone") if button["kind"] == "phone_number" && button["phone_number"].blank?
    end
  end

  def validate_carousel_template_submission
    errors.add(:body, "é obrigatório para apresentar o carrossel") if body.blank?
    cards = clean_carousel_cards
    errors.add(:carousel_cards, "precisa ter entre 2 e 10 cards") unless cards.size.between?(2, 10)

    cards.each_with_index do |card, index|
      position = index + 1
      errors.add(:carousel_cards, "card #{position}: informe o texto") if card["text"].blank?
      errors.add(:carousel_cards, "card #{position}: informe o texto do botão") if card["button_text"].blank?
      errors.add(:carousel_cards, "card #{position}: informe a URL do botão") if card["button_kind"] == "url" && card["button_url"].blank?
      errors.add(:carousel_cards, "card #{position}: informe o telefone do botão") if card["button_kind"] == "phone_number" && card["button_phone_number"].blank?
      errors.add(:carousel_cards, "card #{position}: anexe uma mídia") if card["media_handle"].blank? && carousel_card_media_files.attachments[index].blank? && carousel_card_pending_attachable(index).blank?
    end
  end

  def carousel_card_button(card)
    case card["button_kind"]
    when "quick_reply"
      { type: "QUICK_REPLY", text: card["button_text"].to_s }
    when "phone_number"
      { type: "PHONE_NUMBER", text: card["button_text"].to_s, phone_number: card["button_phone_number"].to_s }
    else
      { type: "URL", text: card["button_text"].to_s, url: card["button_url"].to_s }.tap do |button|
        button[:example] = [card["button_url_example"].to_s] if card["button_url_example"].present?
      end
    end
  end

  def validate_flow_template_submission
    config = clean_flow_config
    errors.add(:body, "é obrigatório para apresentar o Flow") if body.blank?
    errors.add(:flow_config, "precisa ter o ID do Flow") if config["flow_id"].blank?
    errors.add(:flow_config, "precisa ter texto do botão") if config["button_text"].blank?
  end

  def carousel_card_pending_attachable(index)
    change = attachment_changes["carousel_card_media_files"]
    return nil unless change&.respond_to?(:attachables)

    change.attachables[index]
  end

  def header_media_available?
    header_media_file.attached? || header_media_pending_attachable.present? || synced_remote_header_media?
  end

  def header_media_pending_attachable
    attachment_changes["header_media_file"]&.attachable
  end

  def synced_remote_header_media?
    return false unless meta_id.present?

    Array(components).any? do |component|
      attrs = normalize_component(component)
      attrs["type"].to_s.upcase == "HEADER" && attrs["format"].to_s.downcase.in?(%w[image video document])
    end
  end

  def normalize_media_handles
    self.header_media_handle = normalize_media_handle(header_media_handle)
    self.carousel_cards = clean_carousel_cards if carousel_cards.present?
  end

  def normalize_media_handle(value)
    value.to_s.lines.map(&:strip).find(&:present?).to_s
  end

  def normalize_meta_identifier
    normalized = name.to_s.strip.parameterize(separator: "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    self.name = normalized if normalized.present?
  end
end
