require "rails_helper"

# Isolamento do feed de portais: a base de imóveis DEVE partir do tenant da
# integração, nunca do Habitation global (que cruzaria todos os tenants).
# Estes testes usam doubles para ficar independentes do schema — validam a
# lógica de escopo mesmo antes da migration que adiciona tenant_id.
RSpec.describe Portal::EligibilityScope do
  # Relação vazia real para servir de âncora ao encadeamento de scopes.
  let(:empty_relation) { Habitation.none }

  def integration_double(tenant:, has_tenant_column: true)
    instance_double(
      PortalIntegration,
      tenant: tenant,
      allowed_statuses: [],
      allowed_business_types: %w[venda aluguel],
      require_exibir_no_site?: false,
      portal: "zapimoveis"
    ).tap do |integration|
      allow(integration).to receive(:has_attribute?).with(:tenant_id).and_return(has_tenant_column)
    end
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
end
