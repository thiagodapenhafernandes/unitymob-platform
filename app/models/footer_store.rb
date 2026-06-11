class FooterStore < ApplicationRecord
  validates :name, :address, presence: true
  default_scope { order(position: :asc) }
end
