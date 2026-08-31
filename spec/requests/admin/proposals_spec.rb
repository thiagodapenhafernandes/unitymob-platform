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

  describe "GET /admin/leads/:id" do
    it "renderiza criacao e edicao de proposta em modais no contexto do lead" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 1000)

      get admin_lead_path(lead)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)

      new_modal = document.at_css("#newProposalLeadSection#{lead.id}")
      edit_modal = document.at_css("#editProposal#{proposal.id}")

      expect(new_modal).to be_present
      expect(new_modal.at_css("form")["action"]).to eq(admin_lead_proposals_path(lead))
      expect(edit_modal).to be_present
      expect(edit_modal.at_css("form")["action"]).to eq(admin_proposal_path(proposal))
      expect(edit_modal.at_css("input[name='_method']")["value"]).to eq("patch")
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

    it "atualiza o painel operacional do lead via Turbo Stream" do
      lead = create(:lead)

      post admin_lead_proposals_path(lead),
           params: { proposal: { title: "Proposta Turbo", valor: "450.000,00", entrada: "90000", condicoes: "Financiamento" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("pwa_operational_panel_lead_#{lead.id}", "R$ 450.000,00")
    end

    it "não cria proposta nem estoura erro quando o valor vem inválido" do
      lead = create(:lead)

      expect {
        post admin_lead_proposals_path(lead),
             params: { proposal: { title: "Teste", valor: "23424234dw", entrada: "21312312", condicoes: "Teste" } }
      }.not_to change(Proposal, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Valor informe um valor válido")
    end

    it "aceita valores imobiliários acima do limite antigo de integer de 4 bytes" do
      lead = create(:lead)

      expect {
        post admin_lead_proposals_path(lead),
             params: { proposal: { title: "Alto padrão", valor: "23.424.234,00", entrada: "2.131.231,23", condicoes: "Teste" } }
      }.to change(Proposal, :count).by(1)

      proposal = Proposal.last
      expect(proposal.valor_cents).to eq(2_342_423_400)
      expect(proposal.entrada_cents).to eq(213_123_123)
    end
  end

  describe "PATCH /admin/proposals/:id" do
    it "atualiza proposta e registra historico no lead" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 1000)

      expect {
        patch admin_proposal_path(proposal), params: { proposal: { title: "Proposta revisada", valor: "2.000,00" } }
      }.to change { lead.activities.where(kind: "proposal_updated").count }.by(1)

      expect(response).to redirect_to(admin_lead_path(lead))
      expect(proposal.reload.title).to eq("Proposta revisada")
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
