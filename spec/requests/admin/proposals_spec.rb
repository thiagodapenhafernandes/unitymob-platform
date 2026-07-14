require "rails_helper"

RSpec.describe "Admin::Proposals", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "prop-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET new / edit (render dos formulários)" do
    it "renderiza o formulário de nova proposta" do
      lead = create(:lead)
      get new_admin_lead_proposal_path(lead)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nova proposta")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".ax-workspace-heading")).to be_present
      expect(document.at_css(".ax-operational-panel .ax-field-grid")).to be_present
      expect(document.css(".ax-currency-field").size).to eq(2)
      expect(document.at_css(".ax-date-field [data-controller='ax-clear-field']")).to be_present
      expect(document.css(".ax-operational-panel [style]")).to be_empty
    end

    it "renderiza o formulário de edição" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 1000)
      get edit_admin_proposal_path(proposal)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Editar proposta")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".ax-workspace-heading__scope").text).to include(proposal.status_label)
      expect(document.at_css(".ax-form-actions")).to be_present
    end
  end

  describe "POST /admin/leads/:lead_id/proposals" do
    it "cria proposta com token e valor em centavos" do
      lead = create(:lead)

      expect {
        post admin_lead_proposals_path(lead), params: { proposal: { valor: "450.000,00", entrada: "90000", condicoes: "Financiamento" } }
      }.to change(Proposal, :count).by(1)

      proposal = Proposal.last
      expect(proposal.public_token).to be_present
      expect(proposal.valor_cents).to eq(45_000_000)
      expect(proposal.entrada_cents).to eq(9_000_000)
      expect(lead.activities.where(kind: "proposal_created").count).to eq(1)
    end
  end

  describe "PATCH /admin/proposals/:id/send_proposal" do
    it "marca como enviada e loga na timeline" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 1000)

      patch send_proposal_admin_proposal_path(proposal)

      expect(proposal.reload.status).to eq("enviada")
      expect(proposal.sent_at).to be_present
      expect(lead.activities.where(kind: "proposal_sent").count).to eq(1)
    end
  end

  describe "GET /admin/proposals/:id/pdf" do
    it "gera o PDF da proposta" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 45_000_000, condicoes: "À vista")

      get pdf_admin_proposal_path(proposal)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.body[0, 4]).to eq("%PDF")
    end
  end
end
