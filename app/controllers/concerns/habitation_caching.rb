module HabitationCaching
  extend ActiveSupport::Concern

  included do
    # Default cache expiration times
    INDEX_CACHE_EXPIRATION = 15.minutes
    SHOW_CACHE_EXPIRATION = 1.hour
  end

  private

  def cache_index_page
    expires_in INDEX_CACHE_EXPIRATION, public: true
  end

  def cache_show_page(habitation)
    fresh_when(
      etag: [habitation, public_show_asset_cache_key],
      last_modified: habitation.updated_at,
      public: true
    )
  end

  def public_show_asset_cache_key
    [
      "public-private-area-v1",
      asset_cache_path("tailwind.css"),
      asset_cache_path("application.css"),
      asset_cache_path("ax_toast.css"),
      Rails.root.join("app/views/layouts/application.html.erb").mtime.to_i
    ].join(":")
  end

  def asset_cache_path(logical_path)
    helpers.asset_path(logical_path)
  rescue StandardError
    logical_path
  end
end
