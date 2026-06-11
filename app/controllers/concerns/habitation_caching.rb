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
    fresh_when(habitation, public: true)
  end
end
