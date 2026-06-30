require "rails_helper"

RSpec.describe AiPropertyBatchSuggestionJob, type: :job do
  it "processa apenas imoveis do tenant informado" do
    tenant = Tenant.create!(name: "Conta IA #{SecureRandom.hex(3)}", slug: "conta-ia-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outra IA #{SecureRandom.hex(3)}", slug: "outra-ia-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, :admin, tenant: tenant)
    current_habitation = create(:habitation, tenant: tenant, codigo: "AI-CUR-#{SecureRandom.hex(3)}")
    other_habitation = create(:habitation, tenant: other_tenant, codigo: "AI-OUT-#{SecureRandom.hex(3)}")
    processed = []
    service = instance_double(Ai::PropertyContentService, generate_suggestion!: true)

    allow(Ai::PropertyContentService).to receive(:new) do |habitation, admin_user:|
      processed << [habitation, admin_user]
      service
    end

    described_class.perform_now(triggered_by_id: admin.id, tenant_id: tenant.id)

    expect(processed).to contain_exactly([current_habitation, admin])
    expect(processed.flatten).not_to include(other_habitation)
  end

  it "nao passa usuario disparador de outro tenant para o servico" do
    tenant = Tenant.create!(name: "Conta IA destino #{SecureRandom.hex(3)}", slug: "conta-ia-destino-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Conta IA usuario #{SecureRandom.hex(3)}", slug: "conta-ia-usuario-#{SecureRandom.hex(3)}")
    other_admin = create(:admin_user, :admin, tenant: other_tenant)
    current_habitation = create(:habitation, tenant: tenant, codigo: "AI-CUR-USER-#{SecureRandom.hex(3)}")
    processed = []
    service = instance_double(Ai::PropertyContentService, generate_suggestion!: true)

    allow(Ai::PropertyContentService).to receive(:new) do |habitation, admin_user:|
      processed << [habitation, admin_user]
      service
    end

    described_class.perform_now(triggered_by_id: other_admin.id, tenant_id: tenant.id)

    expect(processed).to contain_exactly([current_habitation, nil])
  end
end
