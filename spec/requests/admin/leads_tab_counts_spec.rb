require "rails_helper"

RSpec.describe "Admin leads tab counts", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "tabcounts-#{SecureRandom.hex(8)}@salute.test") }
  let(:tenant) { admin.tenant }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "verify scope index" do
    it "serves unverified_inquiries from the partial index instead of seq-scanning leads" do
      scope = tenant.leads.unverified_inquiries
      ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
      expect(scope.explain).to include("idx_leads_unverified_inquiries")
    end
  end

  describe "PWA tab count scoping" do
    let(:controller) do
      current_tenant = tenant
      current_admin = admin
      Admin::LeadsController.new.tap do |ctrl|
        ctrl.define_singleton_method(:current_tenant) { current_tenant }
        ctrl.define_singleton_method(:current_admin_user) { current_admin }
      end
    end

    it "computes only the requested tabs" do
      counts = controller.send(:lead_tab_counts_for, tenant.leads, only: %w[todo visits future favorites all])

      expect(counts.keys).to match_array(%w[todo visits future favorites all])
    end

    it "keeps verify in the default tab set" do
      counts = controller.send(:lead_tab_counts_for, tenant.leads)

      expect(counts).to include("verify")
    end
  end
end
