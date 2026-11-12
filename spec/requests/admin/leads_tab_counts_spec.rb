require "rails_helper"

RSpec.describe "Admin leads tab counts", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "tabcounts-#{SecureRandom.hex(8)}@salute.test") }
  let(:tenant) { admin.tenant }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renders the active total immediately and applies the search to deferred totals" do
    matching = create(:lead, tenant: tenant, admin_user: admin, name: "Busca específica")
    other = create(:lead, tenant: tenant, admin_user: admin, name: "Outro contato")
    [matching, other].each { |lead| LeadFavorite.create!(tenant: tenant, admin_user: admin, lead: lead) }

    get admin_leads_path(view: "list", q: matching.name)
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#lead_desktop_tab_count_all").text.strip).to eq("1")
    expect(page.at_css("#lead_desktop_tab_count_favorites").text.strip).to eq("–")

    get page.at_css("#lead_desktop_tab_counts")["data-ax-media-frame-src-value"],
        headers: { "Turbo-Frame" => "lead_desktop_tab_counts" }
    expect(response).to have_http_status(:ok)
    counts = Nokogiri::HTML(response.body).at_css("turbo-frame#lead_desktop_tab_counts")
    expect(counts.at_css('turbo-stream[target="lead_desktop_tab_count_favorites"] template').text.strip).to eq("1")
    expect(counts.at_css('turbo-stream[target="lead_desktop_tab_count_all"]')).to be_nil
  end

  it "hides confirmed internal Directs from rows and totals while preserving their history" do
    admin.update!(instagram_username: "corretor")
    admin.update_columns(instagram_direct_ids: { "100" => "200" })
    internal = create(:lead, tenant: tenant, admin_user: admin, name: "Direct interno",
                      instagram_account_id: "100", instagram_scoped_id: "200")
    external = create(:lead, tenant: tenant, admin_user: admin, name: "Direct externo",
                      instagram_account_id: "101", instagram_scoped_id: "200")
    [internal, external].each { |lead| LeadFavorite.create!(tenant: tenant, admin_user: admin, lead: lead) }

    get admin_leads_path(view: "list")
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#lead_#{external.id}")).to be_present
    expect(page.at_css("#lead_#{internal.id}")).to be_nil
    expect(page.at_css("#lead_desktop_tab_count_all").text.strip).to eq("1")

    get page.at_css("#lead_desktop_tab_counts")["data-ax-media-frame-src-value"],
        headers: { "Turbo-Frame" => "lead_desktop_tab_counts" }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('turbo-stream[target="lead_desktop_tab_count_favorites"] template').text.strip).to eq("1")
    expect(internal.reload.instagram_scoped_id).to eq("200")
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
        ctrl.params = {}
        ctrl.define_singleton_method(:current_tenant) { current_tenant }
        ctrl.define_singleton_method(:current_admin_user) { current_admin }
      end
    end

    it "mantém contador e lista de favoritos alinhados ao encerramento C2S" do
      integration = create(:external_lead_integration, tenant: tenant, connected_by_admin_user: admin,
        operational_mappings: {"mirror_c2s_owners" => true})
      active = create(:lead, tenant: tenant, admin_user: admin, external_lead_integration: integration)
      closed = create(:lead, tenant: tenant, admin_user: admin, external_lead_integration: integration, status: "Negócio fechado")
      [active, closed].each { |lead| create(:lead_favorite, tenant: tenant, admin_user: admin, lead: lead) }
      expect(controller.send(:lead_scope_for_tab, tenant.leads, "favorites").pluck(:id)).to eq([active.id])
      expect(controller.send(:lead_tab_counts_for, tenant.leads, only: %w[favorites])).to eq("favorites" => 1)
      expect(controller.send(:pwa_lead_scope_for_tab, tenant.leads, "favorites").pluck(:id)).to eq([active.id])
      expect(LeadFavorite.where(tenant: tenant, admin_user: admin).count).to eq(2)
    end

    it "inclui mensagem C2S não respondida em A fazer mesmo com retorno futuro, preservando tarefas" do
      integration = create(:external_lead_integration, tenant: tenant, connected_by_admin_user: admin,
        operational_mappings: {"mirror_c2s_owners" => true})
      lead = create(:lead, tenant: tenant, admin_user: admin, external_lead_integration: integration,
        other_information: {"external_lead_payload" => {"messages" => [{"sender_type" => "Customer", "read_at" => nil}]}})
      task = create(:task, tenant: tenant, admin_user: admin, lead: lead, due_at: 2.days.from_now, status: "pendente")
      expect(controller.send(:lead_scope_for_tab, tenant.leads, "todo")).to include(lead)
      expect(controller.send(:pwa_lead_scope_for_tab, tenant.leads, "future")).to include(lead)
      expect(controller.send(:lead_tab_counts_for, tenant.leads, only: %w[todo future])).to eq("todo" => 1, "future" => 1)
      expect(task.reload.status).to eq("pendente")
      lead.update_columns(other_information: {"external_lead_payload" => {"messages" => [{"sender_type" => "Customer", "read_at" => Time.current.iso8601}]}})
      expect(controller.send(:lead_scope_for_tab, tenant.leads, "todo")).not_to include(lead)
      lead.update_columns(other_information: {"external_lead_payload" => {"messages" => [{"sender_type" => "SysUser", "read_at" => nil}]}})
      expect(controller.send(:lead_scope_for_tab, tenant.leads, "todo")).not_to include(lead)
    end

    it "não inclui mensagens externas sem espelhamento e exclui encerrados das três abas espelhadas" do
      integration = create(:external_lead_integration, tenant: tenant, connected_by_admin_user: admin,
        operational_mappings: {"mirror_c2s_owners" => false})
      lead = create(:lead, tenant: tenant, admin_user: admin, external_lead_integration: integration,
        other_information: {"external_lead_payload" => {"messages" => [{"sender_type" => "Customer", "read_at" => nil}]}})
      create(:task, tenant: tenant, admin_user: admin, lead: lead, due_at: 2.days.from_now, status: "pendente")
      expect(controller.send(:lead_scope_for_tab, tenant.leads, "todo")).not_to include(lead)
      integration.update!(operational_mappings: {"mirror_c2s_owners" => true})
      lead.update_columns(status: "Negócio fechado")
      %w[todo visits future].each do |tab|
        expect(controller.send(:lead_scope_for_tab, tenant.leads, tab)).not_to include(lead)
      end
      expect(controller.send(:lead_scope_for_tab, tenant.leads, "all")).to include(lead)
    end

    it "computes only the requested tabs" do
      counts = controller.send(:lead_tab_counts_for, tenant.leads, only: %w[todo visits future favorites all])

      expect(counts.keys).to match_array(%w[todo visits future favorites all])
    end

    it "keeps verify in the default tab set" do
      counts = controller.send(:lead_tab_counts_for, tenant.leads)

      expect(counts).to include("verify")
    end

    it "usa a mesma exclusão de arquivados nos contadores e cards, preservando o histórico filtrado" do
      active = create(:lead, tenant: tenant, admin_user: admin)
      archived = create(:lead, tenant: tenant, admin_user: admin)
      archived.update_columns(archived_at: Time.current)
      scope = tenant.leads.where(id: [active.id, archived.id])
      expect(controller.send(:lead_tab_counts_for, scope, only: %w[all])).to eq("all" => 1)
      expect(controller.send(:lead_scope_for_tab, scope, "all").pluck(:id)).to eq([active.id])
      controller.instance_variable_set(:@status_filters, [archived.status])
      expect(controller.send(:lead_scope_for_tab, scope, "all").pluck(:id)).to match_array([active.id, archived.id])
      controller.instance_variable_set(:@status_filters, [])
      controller.instance_variable_set(:@attention_filter, "archived_unsuccessful")
      expect(controller.send(:lead_scope_for_tab, scope, "all").pluck(:id)).to include(archived.id)
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
        ctrl.params = {}
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
