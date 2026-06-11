class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true
  before_validation :normalize_imediacoes

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
