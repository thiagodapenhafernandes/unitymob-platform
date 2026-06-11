Rails.application.configure do
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_CACHE_URL", "redis://localhost:6379/1"),
    expires_in: 1.hour,
    namespace: "unitymob_cache",
    reconnect_attempts: 3
  }
end
