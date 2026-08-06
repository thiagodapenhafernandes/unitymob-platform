require "rails_helper"

RSpec.describe "Portal feeds", type: :request do
  before { host! "localhost" }

  def create_integration(portal: "vivareal_vrsync", tenant: Current.tenant, feed_token: SecureRandom.hex(16))
    PortalIntegration.find_or_initialize_by(
      tenant: tenant,
      portal: portal
    ).tap do |integration|
      integration.assign_attributes(
        enabled: true,
        allowed_statuses: Habitation::STATUS_OPTIONS,
        allowed_business_types: %w[venda aluguel],
        feed_token: feed_token
      )
      integration.save!
    end
  end

  def create_chaves_habitation(tenant:, codigo:, title:)
    create(
      :habitation,
      tenant: tenant,
      codigo: codigo,
      titulo_anuncio: title,
      descricao_web: "Descrição pronta para publicação no Chaves na Mão.",
      categoria: "Apartamento",
      status: "Venda",
      valor_venda_cents: 850_000_00,
      valor_locacao_cents: 0,
      exibir_no_site_flag: true,
      publicar_chaves_na_mao: true
    )
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

  it "does not return 304 for Chaves na Mão when the feed serializer version changes" do
    old_versions = { "chaves_xml" => "chaves_xml_old" }
    new_versions = { "chaves_xml" => "chaves_xml_v2" }
    integration = create_integration(portal: "chavesnamao")

    stub_const("Integrations::Portals::FeedsController::FEED_CACHE_VERSIONS", old_versions)
    get integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token)
    stale_etag = response.headers.fetch("ETag")

    stub_const("Integrations::Portals::FeedsController::FEED_CACHE_VERSIONS", new_versions)
    get integrations_portals_feed_token_path(portal: integration.portal, token: integration.feed_token),
        headers: { "If-None-Match" => stale_etag }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<Document>")
  end

  it "creates independent portal tokens for each tenant on the same portal" do
    first_tenant = Tenant.create!(name: "Conta A #{SecureRandom.hex(3)}", slug: "conta-a-#{SecureRandom.hex(4)}")
    second_tenant = Tenant.create!(name: "Conta B #{SecureRandom.hex(3)}", slug: "conta-b-#{SecureRandom.hex(4)}")

    first_integration = PortalIntegration.for_portal!("chavesnamao", tenant: first_tenant)
    second_integration = PortalIntegration.for_portal!("chavesnamao", tenant: second_tenant)

    expect(first_integration).to be_persisted
    expect(second_integration).to be_persisted
    expect(first_integration.tenant).to eq(first_tenant)
    expect(second_integration.tenant).to eq(second_tenant)
    expect(first_integration.feed_token).to be_present
    expect(second_integration.feed_token).to be_present
    expect(first_integration.feed_token).not_to eq(second_integration.feed_token)
  end

  it "serves only the catalog from the tenant that owns the feed token" do
    own_tenant = Tenant.create!(name: "Conta própria #{SecureRandom.hex(3)}", slug: "conta-propria-#{SecureRandom.hex(4)}")
    other_tenant = Tenant.create!(name: "Conta externa #{SecureRandom.hex(3)}", slug: "conta-externa-#{SecureRandom.hex(4)}")
    own_integration = create_integration(portal: "chavesnamao", tenant: own_tenant)
    other_integration = create_integration(portal: "chavesnamao", tenant: other_tenant)

    create_chaves_habitation(tenant: own_tenant, codigo: "OWN-CNM", title: "Imóvel do tenant correto")
    create_chaves_habitation(tenant: other_tenant, codigo: "OTHER-CNM", title: "Imóvel de outro tenant")

    get integrations_portals_feed_token_path(portal: own_integration.portal, token: own_integration.feed_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OWN-CNM")
    expect(response.body).not_to include("OTHER-CNM")

    get integrations_portals_feed_token_path(portal: other_integration.portal, token: other_integration.feed_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OTHER-CNM")
    expect(response.body).not_to include("OWN-CNM")

    get integrations_portals_feed_token_path(portal: "imovelweb", token: own_integration.feed_token)

    expect(response).to have_http_status(:unauthorized)
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
