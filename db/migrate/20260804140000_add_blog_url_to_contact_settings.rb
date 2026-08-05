class AddBlogUrlToContactSettings < ActiveRecord::Migration[7.1]
  SALUTE_BLOG_URL = "https://blog.saluteimoveis.com".freeze
  SALUTE_YOUTUBE_URL = "https://www.youtube.com/channel/UC9BG_PI0pFj-m65sR6KeZtA".freeze

  def change
    add_column :contact_settings, :blog_url, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE contact_settings
             SET blog_url = COALESCE(NULLIF(blog_url, ''), #{quote(SALUTE_BLOG_URL)}),
                 youtube_url = COALESCE(NULLIF(youtube_url, ''), #{quote(SALUTE_YOUTUBE_URL)}),
                 updated_at = CURRENT_TIMESTAMP
            FROM tenants
           WHERE contact_settings.tenant_id = tenants.id
             AND tenants.slug = 'default'
        SQL
      end
    end
  end
end
