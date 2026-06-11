class Constructor < ApplicationRecord
  has_many :habitations, dependent: :nullify
  
  has_one_attached :logo
  
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  def favicon_url
    return nil if website_url.blank?
    "https://www.google.com/s2/favicons?sz=64&domain=#{website_url}"
  end

  def dynamic_logo_url
    return nil unless logo.attached?
    Rails.application.routes.url_helpers.rails_blob_path(logo, only_path: true)
  end
end
