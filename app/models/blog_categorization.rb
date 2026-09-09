class BlogCategorization < ApplicationRecord
  belongs_to :blog_article, touch: true
  belongs_to :blog_category
  validate :same_tenant

  private

  def same_tenant
    errors.add(:blog_category, "deve pertencer à mesma conta") if blog_article && blog_category && blog_article.tenant_id != blog_category.tenant_id
  end
end
