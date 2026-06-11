class FooterSocialLink < ApplicationRecord
  validates :platform, :url, presence: true
  default_scope { order(position: :asc) }
  
  def icon_class
    case platform.downcase
    when 'facebook' then 'bi-facebook'
    when 'instagram' then 'bi-instagram'
    when 'linkedin' then 'bi-linkedin'
    when 'youtube' then 'bi-youtube'
    when 'tiktok' then 'bi-tiktok'
    when 'whatsapp' then 'bi-whatsapp'
    else 'bi-share'
    end
  end
end
