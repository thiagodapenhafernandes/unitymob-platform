# frozen_string_literal: true

class AccountRoute < ApplicationRecord
  self.primary_key = "id"

  validates :email, :target_url, presence: true
  validates :email, uniqueness: { case_sensitive: false }

  before_validation :normalize_email

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
