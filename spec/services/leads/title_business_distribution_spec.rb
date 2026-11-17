require 'rails_helper'

RSpec.describe 'Distribuição pela modalidade do título' do
  let(:tenant) { Tenant.default }
  let(:property) { create(:habitation, tenant: tenant, valor_venda_cents: 50000000, valor_locacao_cents: 750000) }
  let(:sale_rule) { create(:distribution_rule, tenant: tenant, source_site: false, source_meta: true, business_type: :venda) }
  let(:rent_rule) { create(:distribution_rule, tenant: tenant, source_site: false, source_meta: true, business_type: :locacao) }

  { '9846 | Edifício Ruth de Sá | Aluguel' => :locacao, '[Compra] Edifício Ruth de Sá 9846' => :venda }.each do |title, type|
    it "seleciona a fila de #{type} pelo título mesmo com imóvel de venda e locação" do
      Current.set(tenant: tenant) do
        sale_rule
        rent_rule
        lead = build(:lead, tenant: tenant, origin: 'Facebook Lead Ads', product: title, property_id: property.id)
        expected = type == :locacao ? rent_rule : sale_rule
        expect(Leads::DistributorService.new(lead).matching_entry_rule).to eq(expected)
      end
    end
  end
end
