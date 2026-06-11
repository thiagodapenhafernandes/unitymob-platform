class FooterLink < ApplicationRecord
  validates :label, :url, presence: true
  default_scope { order(position: :asc) }
end
