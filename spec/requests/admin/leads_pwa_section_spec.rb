require "rails_helper"

RSpec.describe "Admin leads PWA section", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "pwasection-#{SecureRandom.hex(8)}@salute.test") }
  let(:tenant) { admin.tenant }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET index" do
    it "lazy-loads the PWA section instead of embedding it" do
      pipeline = create(:lead_pipeline, tenant: tenant)
      create(:lead, tenant: tenant, name: "Lazy Lead", lead_pipeline: pipeline)

      get admin_lead_pipeline_leads_path(pipeline, view: "kanban")

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      frame = document.at_css("turbo-frame#lead_pwa_section")
      expect(frame).to be_present
      expect(frame["loading"]).to eq("lazy")
      expect(frame["target"]).to eq("_top")
      expect(frame["src"]).to include("pwa_section")
      expect(frame["src"]).to include("lead_pipeline_id=#{pipeline.id}")
      expect(document.css("section.lead-pwa-screen")).to be_empty
    end
  end

  describe "GET pwa_section" do
    it "renders the PWA section standalone with leads and counts" do
      create(:lead, tenant: tenant, name: "PWA Section Lead", status: "Novo")

      get pwa_section_admin_leads_path(view: "list", mobile_tab: "all")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lead-pwa-screen")
      expect(response.body).to include("PWA Section Lead")
      document = Nokogiri::HTML(response.body)
      frame = document.at_css("turbo-frame#lead_pwa_section")
      expect(frame["target"]).to eq("_top")
      expect(frame.at_css("a.lead-pwa-tab[href*='mobile_tab=all']")).to be_present
      expect(frame.at_css("form.lead-pwa-search")["action"]).to eq(admin_leads_path)
      card = frame.at_css("a.lead-pwa-card")
      expect(card).to be_present
      return_to = Rack::Utils.parse_query(URI.parse(card["href"]).query).fetch("return_to")
      expect(URI.parse(return_to).path).to eq(admin_leads_path)
      expect(Rack::Utils.parse_query(URI.parse(return_to).query)).to include("view" => "list", "mobile_tab" => "all")
    end

    it "keeps the pipeline scope from params" do
      pipeline = create(:lead_pipeline, tenant: tenant)
      other_pipeline = create(:lead_pipeline, tenant: tenant)
      create(:lead, tenant: tenant, name: "Scoped Lead", lead_pipeline: pipeline, status: "Novo")
      create(:lead, tenant: tenant, name: "Other Lead", lead_pipeline: other_pipeline, status: "Novo")

      get pwa_section_admin_leads_path(view: "list", mobile_tab: "all", lead_pipeline_id: pipeline.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Scoped Lead")
      expect(response.body).not_to include("Other Lead")
    end
  end
end
