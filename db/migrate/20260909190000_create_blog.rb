class CreateBlog < ActiveRecord::Migration[7.1]
  def change
    create_table :blog_categories do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :blog_categories, [:tenant_id, :slug], unique: true
    add_index :blog_categories, [:tenant_id, :name], unique: true

    create_table :blog_articles do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :excerpt
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.string :cover_alt
      t.string :meta_title
      t.string :meta_description
      t.integer :wordpress_id
      t.string :source_url
      t.timestamps
    end
    add_index :blog_articles, [:tenant_id, :slug], unique: true
    add_index :blog_articles, [:tenant_id, :wordpress_id], unique: true
    add_index :blog_articles, [:tenant_id, :status, :published_at, :id], name: "index_blog_articles_public_listing"
    add_check_constraint :blog_articles, "status IN ('draft', 'published')", name: "blog_article_status"
    add_check_constraint :blog_articles, "status != 'published' OR published_at IS NOT NULL", name: "blog_article_publication_date"

    create_table :blog_categorizations do |t|
      t.references :blog_article, null: false, foreign_key: true
      t.references :blog_category, null: false, foreign_key: true
    end
    add_index :blog_categorizations, [:blog_article_id, :blog_category_id], unique: true, name: "index_blog_categorizations_unique"
  end
end
