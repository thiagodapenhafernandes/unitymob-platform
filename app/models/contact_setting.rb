class ContactSetting < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  PROPERTY_LEAD_MESSAGE_TYPES = {
    "sale" => {
      label: "Venda",
      success_attribute: :sale_lead_success_message,
      whatsapp_attribute: :sale_whatsapp_message
    },
    "rent" => {
      label: "Locação",
      success_attribute: :rent_lead_success_message,
      whatsapp_attribute: :rent_whatsapp_message
    },
    "sale_rent" => {
      label: "Venda e locação",
      success_attribute: :sale_rent_lead_success_message,
      whatsapp_attribute: :sale_rent_whatsapp_message
    }
  }.freeze

  PROPERTY_LEAD_VARIABLES = {
    "{nome}" => "Nome informado no modal",
    "{imovel}" => "Título do imóvel",
    "{codigo}" => "Código do imóvel",
    "{tipo}" => "Venda, Locação ou Venda e locação"
  }.freeze

  DEFAULT_PROPERTY_LEAD_SUCCESS_MESSAGE = "Recebemos seu contato. Um corretor da nossa equipe irá falar com você em breve.".freeze
  DEFAULT_PROPERTY_WHATSAPP_MESSAGE = "Olá, estou interessado no imóvel {imovel} (Código: {codigo}). Gostaria de mais informações.".freeze

  FOOTER_SOCIAL_LINK_FIELDS = [
    ["Facebook", :facebook_url],
    ["Instagram", :instagram_url],
    ["YouTube", :youtube_url],
    ["Blog", :blog_url],
    ["LinkedIn", :linkedin_url]
  ].freeze

  after_commit :clear_public_site_cache
  normalize_phone_fields :whatsapp_primary, :whatsapp_secondary, :phone

  # Singleton pattern
  def self.instance(tenant: Current.tenant || Tenant.public_for)
    raise ArgumentError, "Tenant obrigatório para configurações de contato" if tenant.blank?

    where(tenant: tenant).first_or_create!
  end

  def footer_social_links
    FOOTER_SOCIAL_LINK_FIELDS.filter_map do |platform, attribute|
      url = public_send(attribute).presence
      FooterSocialLink.new(platform:, url:) if url
    end
  end

  def property_lead_success_message_for(negotiation_type, lead: nil, habitation: nil)
    template = property_message_template_for(negotiation_type, :success_attribute, DEFAULT_PROPERTY_LEAD_SUCCESS_MESSAGE)
    interpolate_property_lead_message(template, negotiation_type:, lead:, habitation:)
  end

  def property_whatsapp_message_for(negotiation_type, lead: nil, habitation: nil, fallback: nil)
    template = property_message_template_for(negotiation_type, :whatsapp_attribute, fallback.presence || DEFAULT_PROPERTY_WHATSAPP_MESSAGE)
    interpolate_property_lead_message(template, negotiation_type:, lead:, habitation:)
  end

  def self.property_lead_message_label_for(negotiation_type)
    PROPERTY_LEAD_MESSAGE_TYPES.dig(negotiation_type.to_s, :label) || PROPERTY_LEAD_MESSAGE_TYPES.dig("sale", :label)
  end

  private

  def property_message_template_for(negotiation_type, attribute_key, fallback)
    config = PROPERTY_LEAD_MESSAGE_TYPES[negotiation_type.to_s] || PROPERTY_LEAD_MESSAGE_TYPES.fetch("sale")
    public_send(config.fetch(attribute_key)).presence || fallback
  end

  def interpolate_property_lead_message(template, negotiation_type:, lead:, habitation:)
    values = {
      "{nome}" => lead&.name.to_s.squish.presence || "cliente",
      "{imovel}" => property_title_for_message(habitation),
      "{codigo}" => habitation&.codigo.to_s.squish.presence || "não informado",
      "{tipo}" => self.class.property_lead_message_label_for(negotiation_type)
    }

    values.reduce(template.to_s) { |message, (token, value)| message.gsub(token, value) }
  end

  def property_title_for_message(habitation)
    return "o imóvel informado" unless habitation

    title = habitation.respond_to?(:display_title) ? habitation.display_title : habitation.titulo_anuncio
    title.to_s.squish.presence || "o imóvel informado"
  end

  def clear_public_site_cache
    WhatsappBusinessIntegration.clear_all_site_phone_settings_cache
  end
end
