require "rails_helper"

RSpec.describe Seo::MarketingInsights do
  def attach_photo(habitation)
    habitation.photos.attach(
      io: StringIO.new("fake image"),
      filename: "#{habitation.codigo}.jpg",
      content_type: "image/jpeg"
    )
  end

  around do |example|
    Lead.skip_callback(:commit, :after, :route_lead)
    example.run
  ensure
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "calcula oportunidades de imoveis apenas com habitations e leads do tenant informado" do
    current_tenant = Tenant.default
    other_tenant = Tenant.create!(
      name: "Conta marketing #{SecureRandom.hex(3)}",
      slug: "conta-marketing-#{SecureRandom.hex(3)}"
    )
    current_property = create(
      :habitation,
      tenant: current_tenant,
      codigo: "MKT-CUR-#{SecureRandom.hex(3)}",
      titulo_anuncio: "Apartamento frente mar",
      bairro: "Centro",
      status: "Venda",
      exibir_no_site_flag: true,
      valor_venda_cents: 3_000_000_00
    )
    other_property = create(
      :habitation,
      tenant: other_tenant,
      codigo: "MKT-OUT-#{SecureRandom.hex(3)}",
      titulo_anuncio: "Apartamento externo com muitos sinais",
      bairro: "Barra Sul",
      status: "Venda",
      exibir_no_site_flag: true,
      valor_venda_cents: 5_000_000_00
    )
    attach_photo(current_property)
    attach_photo(other_property)

    create(:lead, tenant: current_tenant, property_id: current_property.id, origin: "site")
    3.times { create(:lead, tenant: other_tenant, property_id: other_property.id, origin: "site") }
    SeoConversionEvent.create!(
      habitation: current_property,
      event_type: "whatsapp_click",
      occurred_at: Time.current
    )
    5.times do
      SeoConversionEvent.create!(
        habitation: other_property,
        event_type: "whatsapp_click",
        occurred_at: Time.current
      )
    end

    insights = described_class.new(tenant: current_tenant).property_insights(limit: 10)

    expect(insights.map(&:habitation)).to contain_exactly(current_property)
    expect(insights.first.lead_count).to eq(1)
    expect(insights.first.page_views).to eq(1)
  end
end
