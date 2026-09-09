class BlogCategory < ApplicationRecord
  include TenantScoped
  has_many :blog_categorizations, dependent: :destroy
  has_many :blog_articles, through: :blog_categorizations
  before_validation { self.name = name.to_s.strip; self.slug = (slug.presence || name).to_s.parameterize }
  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id }
  validates :slug, presence: true, uniqueness: { scope: :tenant_id }
end
