require "rails_helper"

RSpec.describe "Commercial contract proposals", type: :request do
  before { host! "localhost" }

  let(:admin) { create(:admin_user, :admin) }
  let(:proposal) do
    CommercialContractProposal.create!(
      tenant: admin.tenant,
      admin_user: admin,
      legal_business_name: "Cliente B2B Ltda",
      trade_name: "Cliente B2B",
      cnpj: "12.345.678/0001-90",
      client_email: "diretoria@cliente.test"
    )
  end

  it "exibe proposta pública e permite baixar PDF antes do aceite" do
    get commercial_contract_proposal_path(proposal.public_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Baixar proposta em PDF")
    expect(proposal.reload.viewed_at).to be_present

    get proposal_pdf_commercial_contract_proposal_path(proposal.public_token)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body.bytesize).to be > 1_000
  end

  it "envia OTP, aceita contrato e gera contrato final com certificado" do
    ActionMailer::Base.deliveries.clear
    allow(SecureRandom).to receive(:random_number).and_call_original
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(123_456)

    post request_otp_commercial_contract_proposal_path(proposal.public_token), params: {
      commercial_contract_proposal: {
        representative_name: "Maria Contratante",
        representative_cpf: "123.456.789-09",
        representative_role: "Sócia administradora",
        representative_email: "maria@cliente.test",
        representative_phone: "(47) 99999-0000",
        authority_confirmed: "1"
      }
    }

    expect(response).to redirect_to(commercial_contract_proposal_path(proposal.public_token, step: "otp"))
    expect(ActionMailer::Base.deliveries.size).to eq(1)

    post accept_commercial_contract_proposal_path(proposal.public_token), params: { otp_code: "123456" }

    expect(response).to redirect_to(commercial_contract_proposal_path(proposal.public_token))
    proposal.reload
    expect(proposal.status).to eq("accepted")
    expect(proposal.acceptance).to be_present
    expect(proposal.acceptance.contract_pdf).to be_attached
    expect(proposal.acceptance.certificate_pdf).to be_attached
    expect(proposal.acceptance.evidence).to include("terms_hash", "proposal_hash", "ip_address")
  end
end
