class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true

  # Higiene vinda do Vista: espaços sobrando criavam variantes de bairro/cidade
  before_save do
    self.bairro = bairro.to_s.squish.presence if will_save_change_to_bairro?
    self.cidade = cidade.to_s.squish.presence if respond_to?(:cidade) && will_save_change_to_cidade?
  end
  before_validation :normalize_imediacoes
  after_commit :clear_habitation_public_filter_cache, if: :habitation_location_cache_relevant?

  # Validations
  validates :logradouro, :bairro, :cidade, :uf, presence: true
  validates :uf, length: { is: 2 }
  validates :cep, format: { with: /\A\d{5}-?\d{3}\z/, message: "formato inválido (00000-000)" }, allow_blank: true
  
  # Geocoding (Placeholder for future implementation)
  # geocoded_by :full_address
  # after_validation :geocode, if: ->(obj){ obj.logradouro_changed? || obj.cidade_changed? }

  def full_address
    [logradouro, numero, bairro, cidade, uf, pais].compact.join(', ')
  end

  def imediacoes=(value)
    super(normalize_list_value(value))
  end

  private

  def normalize_imediacoes
    self.imediacoes = normalize_list_value(imediacoes)
  end

  def habitation_location_cache_relevant?
    addressable_type == "Habitation" &&
      (previous_changes.key?("cidade") || previous_changes.key?("bairro") || previous_changes.key?("addressable_id"))
  end

  def clear_habitation_public_filter_cache
    tenant_id = addressable&.tenant_id
    return if tenant_id.blank?

    Habitation.clear_public_filter_cache_for_tenant(tenant_id)
  end

  def normalize_list_value(value)
    raw_items =
      case value
      when Array
        value
      when String
        value.split(/[,\n;]+/)
      else
        Array(value)
      end

    raw_items.map { |item| item.to_s.strip }
             .reject(&:blank?)
             .uniq
  end
end
