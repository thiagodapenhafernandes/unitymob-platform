class FooterStore < ApplicationRecord
  include PublicSite::BumpsPageVersion
  include PhoneNormalizable

  validates :name, :address, presence: true
  normalize_phone_fields :phone
  default_scope { order(position: :asc) }

  private

  def public_page_version_tenant_id
    FooterSetting.unscoped.where(id: footer_setting_id).pick(:tenant_id)
  end

end
