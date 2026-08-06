OmniAuth.config.before_request_phase = lambda do |env|
  Auth::OauthSessionCompactor.before_request_phase(env)
end

OmniAuth.config.after_request_phase = lambda do |env|
  Auth::OauthSessionCompactor.after_request_phase(env)
end
