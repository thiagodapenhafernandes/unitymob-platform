class WhatsappBusinessIntegration < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  STATUSES = %w[disconnected connected pending failed canceled].freeze
  NEGOTIATION_TYPES = {
    "sale" => {
      label: "Venda",
      phone_attribute: :sale_whatsapp_number,
      form_attribute: :sale_requires_lead_form,
      default_message: "Leads de imóveis de venda serão enviados para este número."
    },
    "rent" => {
      label: "Locação",
      phone_attribute: :rent_whatsapp_number,
      form_attribute: :rent_requires_lead_form,
      default_message: "Leads de imóveis de locação serão enviados para este número."
    },
    "sale_rent" => {
      label: "Venda e locação",
      phone_attribute: :sale_rent_whatsapp_number,
      form_attribute: :sale_rent_requires_lead_form,
      default_message: "Leads de imóveis disponíveis para venda e locação serão enviados para este número."
    }
  }.freeze
  SITE_PHONE_ATTRIBUTES = %i[
    default_whatsapp_number
    sale_whatsapp_number
    rent_whatsapp_number
    sale_rent_whatsapp_number
    sale_requires_lead_form
    rent_requires_lead_form
    sale_rent_requires_lead_form
  ].freeze
  SITE_PHONE_SETTINGS_CACHE_PREFIX = "public_site:whatsapp_phone_settings".freeze

  belongs_to :connected_by_admin_user, class_name: "AdminUser", optional: true
  has_many :sender_numbers,
           class_name: "WhatsappSenderNumber",
           dependent: :nullify,
           inverse_of: :whatsapp_business_integration

  validates :status, inclusion: { in: STATUSES }
  normalize_phone_fields :default_whatsapp_number,
                         :sale_whatsapp_number,
                         :rent_whatsapp_number,
                         :sale_rent_whatsapp_number
  validate :connected_user_must_belong_to_tenant
  validate :validate_site_phone_numbers
  after_commit :clear_site_phone_settings_cache

  SITE_PHONE_ATTRIBUTES.each do |attribute_name|
    define_method(attribute_name) do
      fallback_site_phone_attribute(attribute_name)
    end

    define_method("#{attribute_name}=") do |value|
      assign_site_phone_attribute(attribute_name, value)
    end
  end

  def self.current(tenant = Current.tenant)
    raise ArgumentError, "Tenant obrigatório para integração WhatsApp" if tenant.blank?

    tenant.whatsapp_business_integrations.order(created_at: :asc).first_or_initialize
  end

  def connected?
    status == "connected" && waba_id.present? && phone_number_id.present?
  end

  # Pode enviar/receber mensagens via Cloud API?
  def messaging_ready?
    access_token.present? && phone_number_id.present?
  end

  # Cutoff da exigência de apresentação: carimbado quando o toggle liga,
  # limpo quando desliga — conversas criadas antes do cutoff ficam isentas.
  before_save :stamp_require_presentation_since

  # Este corretor precisa se apresentar nesta conversa antes de responder?
  def presentation_required_for?(conversation, admin_user)
    return false unless presentation_enabled? && require_presentation?
    return false if conversation.blank? || admin_user.blank?
    return false if require_presentation_since.blank? || conversation.created_at < require_presentation_since

    conversation.last_presentation_at(admin_user).nil?
  end

  # Token de verificação do webhook (gerado sob demanda; cole no painel da Meta).
  def webhook_verify_token!
    return webhook_verify_token if webhook_verify_token.present?

    token = SecureRandom.hex(16)
    update_column(:webhook_verify_token, token) if persisted?
    self.webhook_verify_token = token
    token
  end

  def token_preview
    return nil if access_token.blank?

    "..." + access_token.last(6)
  end

  def self.site_phone_settings
    cached_site_phone_settings(Current.tenant)
  end

  def self.cached_site_phone_settings(tenant = Current.tenant)
    raise ArgumentError, "Tenant obrigatório para configuração pública do WhatsApp" if tenant.blank?

    Rails.cache.fetch(site_phone_settings_cache_key(tenant), expires_in: 5.minutes) do
      current(tenant).site_phone_settings
    end
  end

  def site_phone_settings
    {
      default_phone: Phones::Normalizer.call(default_whatsapp_number.presence || default_contact_whatsapp),
      negotiations: NEGOTIATION_TYPES.transform_values do |config|
        phone = public_send(config[:phone_attribute]).presence || default_whatsapp_number.presence || default_contact_whatsapp
        {
          label: config[:label],
          phone: Phones::Normalizer.call(phone),
          requires_form: public_send(config[:form_attribute]) != false
        }
      end
    }
  end

  def phone_for(negotiation_type)
    settings = site_phone_settings
    settings.dig(:negotiations, negotiation_type.to_s, :phone).presence || settings[:default_phone]
  end

  def requires_form_for?(negotiation_type)
    site_phone_settings.dig(:negotiations, negotiation_type.to_s, :requires_form) != false
  end

  def whatsapp_url_for(habitation:, message:)
    phone = phone_for(habitation&.whatsapp_negotiation_type)
    "https://wa.me/#{phone}?text=#{ERB::Util.url_encode(message)}"
  end

  private

  def fallback_site_phone_attribute(attribute_name)
    return self[attribute_name] if has_attribute?(attribute_name)

    value = instance_variable_get("@#{attribute_name}")
    return true if value.nil? && attribute_name.to_s.end_with?("_requires_lead_form")

    value
  end

  def assign_site_phone_attribute(attribute_name, value)
    if has_attribute?(attribute_name)
      self[attribute_name] = value
    else
      instance_variable_set("@#{attribute_name}", value)
    end
  end

  def default_contact_whatsapp
    ContactSetting.where(tenant_id: tenant_id).pick(:whatsapp_primary).presence || "554733111067"
  end

  def validate_site_phone_numbers
    %i[default_whatsapp_number sale_whatsapp_number rent_whatsapp_number sale_rent_whatsapp_number].each do |attribute|
      value = public_send(attribute).to_s
      next if value.blank?

      errors.add(attribute, "deve ter DDD e número válidos") unless Phones::Normalizer.valid?(value)
    end
  end

  def connected_user_must_belong_to_tenant
    return if connected_by_admin_user.blank? || tenant_id.blank?
    return if connected_by_admin_user.tenant_id == tenant_id

    errors.add(:connected_by_admin_user, "deve pertencer ao mesmo Tenant")
  end

  def stamp_require_presentation_since
    return unless will_save_change_to_require_presentation?

    self.require_presentation_since = require_presentation? ? Time.current : nil
  end

  def clear_site_phone_settings_cache
    Rails.cache.delete(self.class.site_phone_settings_cache_key(tenant))
  end

  def self.site_phone_settings_cache_key(tenant)
    "#{SITE_PHONE_SETTINGS_CACHE_PREFIX}:tenant:#{tenant.id}"
  end

  def self.clear_all_site_phone_settings_cache
    Rails.cache.delete_matched("#{SITE_PHONE_SETTINGS_CACHE_PREFIX}:tenant:*")
  rescue NotImplementedError
    Tenant.find_each { |tenant| Rails.cache.delete(site_phone_settings_cache_key(tenant)) }
  end
end
