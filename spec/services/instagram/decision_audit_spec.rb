require 'rails_helper'

RSpec.describe Instagram::DecisionAudit do
  it 'isola falha de auditoria e mantém a transação operacional utilizável' do
    lead = create(:lead, skip_automatic_routing: true)
    lead.with_lock do
      allow(lead.activities).to receive(:create!) { ActiveRecord::Base.connection.execute('SELECT 1 / 0') }
      expect(described_class.record(lead, message_id: 1, outcome: 'catalog_results')).to be_nil
      lead.update_columns(client_name: 'Maria')
    end
    expect(lead.reload.client_name).to eq('Maria')
  end
end
