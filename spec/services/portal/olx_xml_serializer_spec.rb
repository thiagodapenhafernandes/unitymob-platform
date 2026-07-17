require "rails_helper"

RSpec.describe Portal::OlxXmlSerializer do
  def integration_for(portal)
    PortalIntegration.new(
      tenant: Tenant.default,
      portal: portal,
      enabled: true,
      allowed_statuses: Habitation::STATUS_OPTIONS,
      allowed_business_types: %w[venda aluguel]
    )
  end

  it "keeps the official OLX condominium tag for Imovelweb and emits the legacy-compatible tag" do
    habitation = build(
      :habitation,
      codigo: "COND-XML",
      valor_condominio_cents: 400_00,
      valor_iptu_cents: 84_00
    )

    xml = described_class.new(habitations: [habitation], integration: integration_for("imovelweb")).to_xml

    expect(xml).to include("<PrecoCondominio>400</PrecoCondominio>")
    expect(xml).to include("<ValorCondominio>400</ValorCondominio>")
  end

  it "does not add the Imovelweb compatibility tag for other OLX XML portals" do
    habitation = build(
      :habitation,
      codigo: "COND-XML-2",
      valor_condominio_cents: 400_00
    )

    xml = described_class.new(habitations: [habitation], integration: integration_for("chavesnamao")).to_xml

    expect(xml).to include("<PrecoCondominio>400</PrecoCondominio>")
    expect(xml).not_to include("<ValorCondominio>")
  end
end
