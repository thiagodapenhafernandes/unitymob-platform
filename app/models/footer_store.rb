class FooterStore < ApplicationRecord
  include PhoneNormalizable

  validates :name, :address, presence: true
  normalize_phone_fields :phone
  default_scope { order(position: :asc) }
end
