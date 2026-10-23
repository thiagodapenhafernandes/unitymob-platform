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

    it "reuses equivalent scopes within the request without mixing filters" do
      lead = create(:lead, tenant: tenant, name: "Selecionado")
      create(:lead, tenant: tenant, name: "Outro")
      first = controller.send(:lead_tab_counts_for, tenant.leads, only: %w[all])
      queries = []
      subscriber = ->(*args) { queries << args.last[:sql] unless args.last[:name] == "SCHEMA" }
      repeated = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        controller.send(:lead_tab_counts_for, tenant.leads, only: %w[all])
      end

      expect(repeated).to eq(first)
      expect(queries).to be_empty
      expect(controller.send(:lead_tab_counts_for, tenant.leads.where(id: lead.id), only: %w[all])).to eq("all" => 1)
    end
  end

  describe "tab scope tenant scoping" do
    let(:controller) do
      current_tenant = tenant
      current_admin = admin
      Admin::LeadsController.new.tap do |ctrl|
        ctrl.define_singleton_method(:current_tenant) { current_tenant }
        ctrl.define_singleton_method(:current_admin_user) { current_admin }
      end
    end
    let(:other_tenant) { Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}") }

    it "ignores contact activities from other tenants in the todo scope" do
      lead = create(:lead, tenant: tenant, admin_user: admin, status: "Novo")
      LeadActivity.create!(tenant: tenant, lead: lead, kind: "accepted")
      LeadActivity.create!(tenant: other_tenant, lead: lead, kind: "note")

      ids = controller.send(:pwa_actionable_leads, tenant.leads).pluck(:id)

      expect(ids).to include(lead.id)
    end

    it "ignores external schedules from other tenants in the visits scope" do
      lead = create(:lead, tenant: tenant, admin_user: admin, status: "Novo")
      LeadActivity.create!(
        tenant: other_tenant, lead: lead, kind: "external_scheduled_action",
        metadata: { "raw" => { "schedulated_action_date" => 2.days.from_now.iso8601, "schedulated_action_name" => "Visita ao imóvel" } }
      )

      ids = controller.send(:lead_scope_for_tab, tenant.leads, "visits").pluck(:id)

      expect(ids).not_to include(lead.id)
    end

    it "still matches own-tenant external schedules in the visits scope" do
      lead = create(:lead, tenant: tenant, admin_user: admin, status: "Novo")
      LeadActivity.create!(
        tenant: tenant, lead: lead, kind: "external_scheduled_action",
        metadata: { "raw" => { "schedulated_action_date" => 2.days.from_now.iso8601, "schedulated_action_name" => "Visita ao imóvel" } }
      )

      ids = controller.send(:lead_scope_for_tab, tenant.leads, "visits").pluck(:id)

      expect(ids).to include(lead.id)
    end
  end
end
