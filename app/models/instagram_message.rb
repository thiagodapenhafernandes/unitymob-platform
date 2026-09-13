class InstagramMessage < ApplicationRecord
  belongs_to :lead
  validates :message_id, :occurred_at, presence: true
end
