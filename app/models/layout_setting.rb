class LayoutSetting < ApplicationRecord
  has_one_attached :logo
  has_one_attached :favicon


  validates :primary_color, presence: true
  validates :secondary_color, presence: true
  validates :accent_color, presence: true

  def self.instance
    setting = first_or_initialize(
      primary_color: '#022B3A',
      secondary_color: '#053C5E',
      accent_color: '#BFAB25',
      site_name: 'Salute Imóveis'
    )
    
    # Se já existir mas algum campo estiver nulo (como o accent_color do erro)
    if setting.persisted?
      setting.accent_color ||= '#BFAB25'
      setting.primary_color ||= '#022B3A'
      setting.secondary_color ||= '#053C5E'
      setting.save if setting.changed?
    else
      setting.save!
    end
    
    setting
  end
end
