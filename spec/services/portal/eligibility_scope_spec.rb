require "rails_helper"

# Isolamento do feed de portais: a base de imóveis DEVE partir do tenant da
# integração, nunca do Habitation global (que cruzaria todos os tenants).
# Estes testes usam doubles para validar a lógica de escopo sem depender de
# dados reais de portais.
RSpec.describe Portal::EligibilityScope do
  # Relação vazia real para servir de âncora ao encadeamento de scopes.
  let(:empty_relation) { Habitation.none }

  def integration_double(tenant:)
    instance_double(
      PortalIntegration,
      tenant: tenant,
      allowed_statuses: [],
      allowed_business_types: %w[venda aluguel],
      require_exibir_no_site?: false,
      portal: "zapimoveis"
    )
  end

  describe "#eligible_scope" do
    it "parte de tenant.habitations, nunca do Habitation global" do
      habitations_relation = Habitation.all
      tenant = instance_double(Tenant, habitations: habitations_relation)
      integration = integration_double(tenant: tenant)

      expect(tenant).to receive(:habitations).and_return(habitations_relation)
      # Se alguém reintroduzir Habitation.left_outer_joins direto, este teste
      # não garante a falha, mas a expectativa acima garante que passamos pelo
      # tenant. Não deve levantar.
      expect { described_class.new(integration).eligible_scope }.not_to raise_error
    end

    it "retorna Habitation.none quando a integração não tem tenant (registro órfão)" do
      integration = integration_double(tenant: nil)

      result = described_class.new(integration).eligible_scope

      expect(result).to eq(Habitation.none)
      expect(result.to_a).to be_empty
    end
  end

  describe "#preview" do
    it "retorna contagem zerada quando a integração não tem tenant" do
      integration = integration_double(tenant: nil)

      expect(described_class.new(integration).preview).to eq(
        eligible_count: 0, rejected_count: 0, top_reasons: {}
      )
    end
  end
  it "conta imóveis rejeitados únicos mesmo quando há mais de cinco motivos" do
    tenant = Tenant.create!(name: "Teste isolado", slug: "teste-isolado-#{SecureRandom.hex(4)}")
    eligible = create(:habitation, tenant: tenant)
    rejected = create(:habitation, tenant: tenant, pictures: [], valor_venda_cents: 0,
                                   valor_locacao_cents: 0, exibir_no_site_flag: false,
                                   titulo_anuncio: nil, descricao_web: nil)
    rejected.update_columns(titulo_anuncio: nil, descricao_web: nil)
    create(:habitation, tenant: Tenant.create!(name: "Teste isolado", slug: "teste-isolado-#{SecureRandom.hex(4)}"), pictures: [])
    integration = instance_double(PortalIntegration, tenant: tenant,
      allowed_statuses: ["Locação"], allowed_business_types: ["venda"],
      require_exibir_no_site?: true, portal: "zapimoveis")
    eligible.update_columns(status: "Locação", titulo_anuncio: "Imóvel apto", publicar_zapimoveis: true)
    preview = described_class.new(integration).preview
    expect(preview[:eligible_count]).to eq(1)
    expect(preview[:rejected_count]).to eq(1)
    expect(preview[:top_reasons].values.sum).to be > preview[:rejected_count]
    expect(preview[:top_reasons].size).to eq(5)
  end
end
