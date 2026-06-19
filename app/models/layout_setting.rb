class LayoutSetting < ApplicationRecord
  has_one_attached :logo
  has_one_attached :favicon


  # Cor primária padrão do CRM (admin). O cinza-neutro é a base; esta cor é só o destaque.
  ADMIN_SURFACE_DEFAULT = '#FFFFFF'.freeze
  ADMIN_HEADER_DEFAULT = '#EEF2F7'.freeze
  ADMIN_PRIMARY_DEFAULT = '#365F8F'.freeze
  ADMIN_INK_DEFAULT = '#1F2733'.freeze
  LEGACY_ADMIN_PRIMARY_DEFAULT = '#2563EB'.freeze

  validates :primary_color, presence: true
  validates :secondary_color, presence: true
  validates :accent_color, presence: true

  def self.instance
    defaults = {
      primary_color: '#022B3A',
      secondary_color: '#053C5E',
      accent_color: '#BFAB25',
      admin_primary_color: ADMIN_PRIMARY_DEFAULT,
      site_name: 'Salute Imóveis'
    }
    defaults[:admin_surface_color] = ADMIN_SURFACE_DEFAULT if column_names.include?('admin_surface_color')
    defaults[:admin_header_color] = ADMIN_HEADER_DEFAULT if column_names.include?('admin_header_color')
    defaults[:admin_ink_color] = ADMIN_INK_DEFAULT if column_names.include?('admin_ink_color')

    setting = first_or_initialize(defaults)

    # Se já existir mas algum campo estiver nulo (como o accent_color do erro)
    if setting.persisted?
      setting.accent_color ||= '#BFAB25'
      setting.primary_color ||= '#022B3A'
      setting.secondary_color ||= '#053C5E'
      setting.admin_surface_color ||= ADMIN_SURFACE_DEFAULT if setting.has_attribute?(:admin_surface_color)
      setting.admin_header_color ||= ADMIN_HEADER_DEFAULT if setting.has_attribute?(:admin_header_color)
      setting.admin_ink_color ||= ADMIN_INK_DEFAULT if setting.has_attribute?(:admin_ink_color)
      if setting.admin_primary_color.blank? || setting.admin_primary_color.casecmp?(LEGACY_ADMIN_PRIMARY_DEFAULT)
        setting.admin_primary_color = ADMIN_PRIMARY_DEFAULT
      end
      setting.save if setting.changed?
    else
      setting.save!
    end

    setting
  end
end
