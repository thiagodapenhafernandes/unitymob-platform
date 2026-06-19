require "rails_helper"

RSpec.describe "Public Proposals", type: :request do
  let(:admin) { create(:admin_user, :admin, email: "pub-#{SecureRandom.hex(6)}@salute.test") }

  before { host! "localhost" }

  describe "GET /p/:token" do
    it "exibe a proposta e marca como visualizada" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 45_000_000, status: "enviada")

      get public_proposal_path(proposal.public_token)

      expect(response).to have_http_status(:ok)
      expect(proposal.reload.viewed_at).to be_present
      expect(proposal.status).to eq("visualizada")
      expect(lead.activities.where(kind: "proposal_viewed").count).to eq(1)
    end
  end

  describe "POST /p/:token/decidir" do
    it "aceita a proposta" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 1000, status: "enviada")

      post decide_public_proposal_path(proposal.public_token, decision: "aceita")

      expect(proposal.reload.status).to eq("aceita")
      expect(proposal.responded_at).to be_present
      expect(lead.activities.where(kind: "proposal_aceita").count).to eq(1)
    end

    it "não permite decidir duas vezes" do
      lead = create(:lead)
      proposal = lead.proposals.create!(admin_user: admin, valor_cents: 1000, status: "aceita", responded_at: 1.hour.ago)

      post decide_public_proposal_path(proposal.public_token, decision: "recusada")

      expect(proposal.reload.status).to eq("aceita")
    end
  end
end
