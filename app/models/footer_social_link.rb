class FooterSocialLink < ApplicationRecord
  include PublicSite::BumpsPageVersion
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
    when 'blog' then 'bi-journal-text'
    else 'bi-share'
    end
  end

  private

  def public_page_version_tenant_id
    FooterSetting.unscoped.where(id: footer_setting_id).pick(:tenant_id)
  end

end
