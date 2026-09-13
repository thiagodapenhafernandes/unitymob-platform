require "rails_helper"

RSpec.describe "Facebook OAuth version" do
  it "uses the configured Graph version for authorization and token exchange" do
    configuration = Devise.omniauth_configs.fetch(:facebook)
    strategy = configuration.strategy_class.new(nil, *configuration.args)
    version = ENV['META_API_VERSION'] || 'v24.0'

    expect(strategy.client.authorize_url).to eq("https://www.facebook.com/#{version}/dialog/oauth")
    expect(strategy.client.token_url).to eq("https://graph.facebook.com/#{version}/oauth/access_token")
    expect(strategy.client.site).to eq("https://graph.facebook.com/#{version}")
  end
end
