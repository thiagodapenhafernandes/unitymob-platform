require "rails_helper"

RSpec.describe "Admin commercial contract proposals", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "cria e lista propostas somente do tenant autenticado" do
    other_tenant = Tenant.create!(name: "Outro contrato #{SecureRandom.hex(3)}", slug: "outro-contrato-#{SecureRandom.hex(4)}")
    other_admin = create(:admin_user, :admin, tenant: other_tenant)
    CommercialContractProposal.create!(
      tenant: other_tenant,
      admin_user: other_admin,
      legal_business_name: "Empresa fora do tenant",
      cnpj: "00.000.000/0001-00"
    )

    post admin_commercial_contract_proposals_path, params: {
      commercial_contract_proposal: {
        legal_business_name: "Empresa atual Ltda",
        trade_name: "Empresa atual",
        cnpj: "11.222.333/0001-44",
        client_email: "contato@empresa.test",
        plan_name: "Unitymob completo",
        monthly_fee: "3.000,00",
        setup_fee: "0,00",
        minimum_term_months: "0",
        scope_summary: CommercialContractProposal::DEFAULT_SCOPE,
        external_costs_note: CommercialContractProposal::DEFAULT_EXTERNAL_COSTS
      }
    }

    expect(response).to redirect_to(admin_commercial_contract_proposal_path(CommercialContractProposal.last))
    created = admin.tenant.commercial_contract_proposals.last
    expect(created.legal_business_name).to eq("Empresa atual Ltda")
    expect(created.monthly_fee_cents).to eq(300_000)
    expect(created.external_costs_note).to include("servidor", "storage", "Meta/WhatsApp", "OpenAI/IA")

    get admin_commercial_contract_proposals_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Empresa atual Ltda")
    expect(response.body).not_to include("Empresa fora do tenant")
  end

  it "mostra link público e PDF da proposta no detalhe" do
    proposal = CommercialContractProposal.create!(
      tenant: admin.tenant,
      admin_user: admin,
      legal_business_name: "Cliente detalhe Ltda",
      cnpj: "12.345.678/0001-90"
    )

    get admin_commercial_contract_proposal_path(proposal)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(commercial_contract_proposal_url(proposal.public_token))
    expect(response.body).to include("Proposta PDF")

    get proposal_pdf_admin_commercial_contract_proposal_path(proposal)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
  end

  it "permite publicar versoes de termos por tenant" do
    get admin_commercial_contract_terms_versions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Versões dos termos")

    post admin_commercial_contract_terms_versions_path, params: {
      commercial_contract_terms_version: {
        version: "2026.09",
        title: "Termos Unitymob 2026.09",
        body: "Texto contratual com servidor, storage, Meta/WhatsApp e OpenAI/IA.",
        active: "1"
      }
    }

    terms = admin.tenant.commercial_contract_terms_versions.find_by!(version: "2026.09")
    expect(response).to redirect_to(admin_commercial_contract_terms_version_path(terms))
    expect(terms.document_hash).to be_present
  end
end
