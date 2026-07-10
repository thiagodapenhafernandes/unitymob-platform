require "rails_helper"

RSpec.describe "Portal feeds", type: :request do
  before { host! "localhost" }

  it "returns 304 for an unchanged feed without changing the integration timestamp" do
    tenant = Current.tenant
    integration = PortalIntegration.create!(
      tenant: tenant,
      portal: "vivareal_vrsync",
      enabled: true,
      allowed_statuses: Habitation::STATUS_OPTIONS,
      allowed_business_types: %w[venda aluguel],
      feed_token: SecureRandom.hex(16)
    )
    original_updated_at = integration.updated_at

    get integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token)
    expect(response).to have_http_status(:ok)
    etag = response.headers.fetch("ETag")

    get integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token), headers: { "If-None-Match" => etag }

    expect(response).to have_http_status(:not_modified)
    expect(integration.reload.updated_at).to eq(original_updated_at)
    expect(integration.last_feed_at).to be_present
  end
end
