class DevelopmentAlias < ApplicationRecord
  belongs_to :tenant
  belongs_to :development, class_name: "Habitation"

  before_validation :normalize_name

  validates :name, presence: true, length: { maximum: 160 }
  validates :normalized_name, presence: true, uniqueness: { scope: [:tenant_id, :development_id] }
  validate :development_belongs_to_tenant
  validate :development_record_required

  def self.normalize(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  private

  def normalize_name
    self.name = name.to_s.squish
    self.normalized_name = self.class.normalize(name)
    self.tenant ||= development&.tenant
  end

  def development_belongs_to_tenant
    errors.add(:development, "deve pertencer à mesma conta") if development && tenant_id != development.tenant_id
  end

  def development_record_required
    errors.add(:development, "deve ser um empreendimento") if development && !development.empreendimento?
  end
end
