Rack::Attack.throttle("central/login", limit: 10, period: 5.minutes) { |r| r.ip if r.post? && r.path.start_with?("/login") }
Rack::Attack.throttle("central/activation", limit: 20, period: 5.minutes) { |r| r.ip if r.path == "/activate" }
