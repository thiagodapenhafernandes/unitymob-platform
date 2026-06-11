REDIS_CONFIG = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  reconnect_attempts: 3
}

$redis = ConnectionPool::Wrapper.new(size: 5, timeout: 3) do
  Redis.new(REDIS_CONFIG)
end
