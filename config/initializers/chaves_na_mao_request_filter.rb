# O contrato em homologação pode trazer dados pessoais em campos ainda desconhecidos.
class ChavesNaMaoRequestFilter
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["PATH_INFO"].to_s.start_with?("/webhooks/chaves_na_mao/")
      env["action_dispatch.parameter_filter"] = [/.*/]
      # O controller lê JSON após autenticar e limitar o corpo; o parser Rails não deve antecipar isso.
      env["action_dispatch.request.request_parameters"] = {}
    end
    @app.call(env)
  end
end

Rails.application.config.middleware.insert_before Rails::Rack::Logger, ChavesNaMaoRequestFilter
