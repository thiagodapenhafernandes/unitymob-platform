class ExpandBlogArticleStatuses < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :blog_articles, name: "blog_article_status"
    add_check_constraint :blog_articles, "status IN ('draft', 'scheduled', 'published', 'inactive')", name: "blog_article_status"
    remove_check_constraint :blog_articles, name: "blog_article_publication_date"
    add_check_constraint :blog_articles, "status NOT IN ('published', 'scheduled') OR published_at IS NOT NULL", name: "blog_article_publication_date"
  end

  def down
    execute "UPDATE blog_articles SET status = CASE WHEN status = 'scheduled' THEN 'published' ELSE 'draft' END WHERE status IN ('scheduled', 'inactive')"
    remove_check_constraint :blog_articles, name: "blog_article_status"
    add_check_constraint :blog_articles, "status IN ('draft', 'published')", name: "blog_article_status"
    remove_check_constraint :blog_articles, name: "blog_article_publication_date"
    add_check_constraint :blog_articles, "status != 'published' OR published_at IS NOT NULL", name: "blog_article_publication_date"
  end
end
