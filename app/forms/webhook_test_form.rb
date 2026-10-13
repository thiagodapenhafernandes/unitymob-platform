class WebhookTestForm
  include ActiveModel::Model

  FIELDS = %w[event_name event_id transaction_id event_timestamp lead_id business_type value currency
              email_address phone_number first_name last_name property_code placement pais pais_iso
              gclid gbraid wbraid fbc fbp client_id client_ip_address client_user_agent
              utm_source utm_medium utm_campaign].freeze
  attr_accessor(*FIELDS)

  validates :event_name, :event_id, :transaction_id, :lead_id, presence: true, length: { maximum: 200 }
  validates :event_timestamp, numericality: { only_integer: true, greater_than: 0 }
  validates :value, numericality: { greater_than_or_equal_to: 0 }
  validates :business_type, inclusion: { in: %w[venda locacao] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :pais_iso, format: { with: /\A[A-Z]{2}\z/ }
  validate :bounded_fields
  validate :finite_value

  def initialize(setting, attributes = {})
    @default_payload = setting.test_payload.with_indifferent_access
    defaults = @default_payload.slice(*FIELDS).merge(@default_payload[:user_data].slice(:email_address, :phone_number))
    defaults.merge!(@default_payload.dig(:user_data, :address).slice(:first_name, :last_name))
    super(defaults.merge(attributes.to_h))
  end

  def payload
    result = @default_payload.merge(FIELDS.to_h { |field| [field, public_send(field)] })
    result[:event_timestamp] = event_timestamp.to_i
    result[:value] = value.to_f
    result[:property_id] = property_code
    result[:user_data] = { email_address: email_address, phone_number: phone_number, external_id: lead_id,
                           address: { first_name: first_name, last_name: last_name } }
    result[:data] = result[:data].merge(
      id: lead_id, name: [first_name, last_name].reject(&:blank?).join(" "), email: email_address, phone: phone_number,
      business_type: business_type == "venda" ? "sale" : "rent", value: result[:value], currency: currency, property_code: property_code,
      placement: placement, **result.slice(*Leads::Attribution::TRACKING_KEYS, :client_ip_address, :client_user_agent).symbolize_keys
    )
    result[:source] = { utm: result.slice(*Leads::Attribution::TRACKING_KEYS) }
    result.except(:email_address, :phone_number, :first_name, :last_name).merge(diagnostic: true, origin_form: "test_webhook")
  end

  private

  def finite_value
    errors.add(:value, "deve ser um número finito") unless Float(value, exception: false)&.finite?
  end

  def bounded_fields
    errors.add(:base, "Cada campo deve ter no máximo 2.000 caracteres.") if FIELDS.any? { |field| public_send(field).to_s.length > 2_000 }
  end
end
