require "rails_helper"

RSpec.describe "Portal feeds", type: :request do
  before { host! "localhost" }

  def create_integration
    PortalIntegration.find_or_initialize_by(
      tenant: Current.tenant,
      portal: "vivareal_vrsync"
    ).tap do |integration|
      integration.assign_attributes(
        enabled: true,
        allowed_statuses: Habitation::STATUS_OPTIONS,
        allowed_business_types: %w[venda aluguel],
        feed_token: SecureRandom.hex(16)
      )
      integration.save!
    end
  end

  it "returns 304 for an unchanged feed without changing the integration timestamp" do
    integration = create_integration
    original_updated_at = integration.updated_at

    get integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token)
    expect(response).to have_http_status(:ok)
    etag = response.headers.fetch("ETag")

    get integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token), headers: { "If-None-Match" => etag }

    expect(response).to have_http_status(:not_modified)
    expect(integration.reload.updated_at).to eq(original_updated_at)
    expect(integration.last_feed_at).to be_present
  end

  it "does not serialize the feed body for HEAD requests" do
    integration = create_integration

    expect(Portal::VrsyncXmlSerializer).not_to receive(:new)

    head integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
  end

  it "streams XML without changing the generated document" do
    integration = create_integration

    get integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")
    expect(response.body).to include("<?xml", "<ListingDataFeed")
  end
end
