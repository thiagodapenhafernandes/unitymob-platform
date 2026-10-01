class FooterLink < ApplicationRecord
  include PublicSite::BumpsPageVersion
  validates :label, :url, presence: true
  default_scope { order(position: :asc) }

  private

  def public_page_version_tenant_id
    FooterSetting.unscoped.where(id: footer_setting_id).pick(:tenant_id)
  end

end
