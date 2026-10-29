require "rails_helper"

RSpec.describe "Histórico de leads arquivados", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:owner) { create(:admin_user, :admin) }
  let(:tenant) { owner.tenant }
  let(:broker_profile) do
    Profile.create!(tenant: tenant, name: "Corretor arquivo", axis: "vertical", permissions: {
      "leads" => {"view" => true, "edit" => true, "scope" => "own"},
      "comercial" => {"view" => true, "manage" => true, "scope" => "own"}
    })
  end
  let(:broker) { create(:admin_user, tenant: tenant, profile: broker_profile) }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant) }
  let!(:archived) do
    lead = create(:lead, tenant: tenant, admin_user: broker, lead_pipeline: pipeline, name: "Arquivo restrito da conta")
    lead.update_columns(archived_at: Time.current, archived_by_admin_user_id: broker.id, status: "Descartado")
    lead
  end
  before { host! "localhost" }

  it "mostra ao administrador a lista e paginação desktop/mobile, preservando atribuição" do
    sign_in owner
    get admin_leads_path(view: "kanban", lead_tab: "archived", mobile_tab: "archived")
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('.lead-list-workspace').text).to include(archived.name)
    expect(doc.css('.lead-desktop-tab.is-active').text).to include("Arquivados", "1")
    expect(doc.at_css('a.lead-desktop-tab[href*="lead_tab=all"] small').text.strip).to eq("0")
    get list_page_admin_leads_path(format: :json, lead_tab: "archived")
    expect(response.parsed_body["total"]).to eq(1)
    get pwa_leads_page_admin_leads_path(format: :json, mobile_tab: "archived")
    expect(response.parsed_body["total"]).to eq(1)
    get pwa_section_admin_leads_path(view: "list", mobile_tab: "archived")
    expect(Nokogiri::HTML(response.body).css('.lead-pwa-tabs').text).to include("Arquivados")
    expect(archived.reload.admin_user_id).to eq(broker.id)
    expect(archived.archived_by_admin_user_id).to eq(broker.id)
  end

  it "não revela ao corretor os próprios arquivados mesmo com filtros e acesso direto" do
    InAppNotification.create!(tenant: tenant, admin_user: broker, kind: "lead_event", title: archived.name,
      metadata: {lead_id: archived.id})
    sign_in broker
    get admin_leads_path(view: "list", status: ["Descartado"])
    expect(response.body).not_to include(archived.name, 'lead_tab=archived')
    get list_page_admin_leads_path(format: :json, status: ["Descartado"], q: archived.name)
    expect(response.parsed_body["total"]).to eq(0)
    get pwa_leads_page_admin_leads_path(format: :json, mobile_tab: "all", status: ["Descartado"])
    expect(response.parsed_body["total"]).to eq(0)
    get admin_lead_path(archived, format: :json)
    expect(response).to have_http_status(:not_found)
    get preview_admin_lead_path(archived, format: :json)
    expect(response).to have_http_status(:not_found)
    lost = create(:lead, tenant: tenant, admin_user: broker, lead_pipeline: pipeline, status: "Descartado", name: "Perdido sem arquivamento", skip_automatic_routing: true)
    get list_page_admin_leads_path(format: :json, status: ["Descartado"], q: lost.name)
    expect(response.parsed_body["total"]).to eq(1)
    get admin_leads_path(lead_tab: "archived")
    expect(response).to have_http_status(:forbidden)
    get pwa_section_admin_leads_path(mobile_tab: "archived")
    expect(response).to have_http_status(:forbidden)
  end

  it "não libera arquivados a um perfil com escopo amplo nem mistura contas" do
    broad_profile = Profile.create!(tenant: tenant, name: "Gestor arquivo", axis: "vertical",
      permissions: {"leads" => {"view" => true, "scope" => "all"}})
    manager = create(:admin_user, tenant: tenant, profile: broad_profile)
    expect(manager.owns_all?(:leads)).to be(true)
    expect(Lead.accessible_to_admin(manager, tenant: tenant)).not_to include(archived)
    other = Tenant.create!(name: "Outra conta", slug: "other-archive-#{SecureRandom.hex(4)}")
    expect(Lead.accessible_to_admin(owner, tenant: other)).not_to include(archived)
    sign_in owner
    get list_page_admin_leads_path(format: :json)
    expect(response.parsed_body["total"]).to eq(0)
  end

  it "arquiva sem remover o responsável e retorna o corretor à lista operacional" do
    active = create(:lead, tenant: tenant, admin_user: broker, lead_pipeline: pipeline)
    reason = tenant.attribute_options.for_context("lead").for_category("archive_reason").first ||
      create(:attribute_option, tenant: tenant, context: "lead", category: "archive_reason", name: "Sem interesse")
    sign_in broker
    post archive_admin_lead_path(active), params: {archive_reason_id: reason.id, archive_note: "Cliente pediu encerramento"}
    expect(response).to redirect_to(admin_leads_path)
    expect(active.reload.archived_at).to be_present
    expect(active.admin_user_id).to eq(broker.id)
    expect(active.archived_by_admin_user_id).to eq(broker.id)
  end
end
