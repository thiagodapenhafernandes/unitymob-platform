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
  it "adds page messaging while retaining every existing login scope and callback" do
    configuration = Devise.omniauth_configs.fetch(:facebook)
    strategy = configuration.strategy_class.new(nil, *configuration.args)
    previous = %w[email pages_show_list pages_read_engagement pages_manage_ads pages_manage_metadata ads_management leads_retrieval business_management instagram_basic instagram_manage_messages]
    strategy.instance_variable_set(:@env, Rack::MockRequest.env_for('/admin_users/auth/facebook').merge('rack.session' => {}))
    scopes = strategy.authorize_params.fetch(:scope).split(',')
    expect(scopes).to match_array(previous + ['pages_messaging'])
    expect(scopes.uniq).to eq(scopes)
    if ENV['FACEBOOK_REDIRECT_URI']
      expect(strategy.options[:callback_url]).to eq(ENV.fetch('APP_HOST') + ENV['FACEBOOK_REDIRECT_URI'])
    end
  end

end
