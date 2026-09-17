require "rails_helper"

RSpec.describe "Admin::Profiles index", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "profiles-index-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outra hierarquia #{SecureRandom.hex(3)}", slug: "outra-hierarquia-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista a hierarquia apenas do tenant atual" do
    current_name = "Gestão local #{SecureRandom.hex(4)}"
    other_name = "Gestão externa #{SecureRandom.hex(4)}"
    Profile.create!(tenant: admin.tenant, name: current_name, axis: "vertical", position: 650, permissions: {})
    Profile.create!(tenant: other_tenant, name: other_name, axis: "vertical", position: 650, permissions: {})

    get admin_profiles_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_name, "Perfis de acesso", "Hierarquia e funções")
    expect(response.body).not_to include(other_name)
    expect(response.body).to include(new_admin_profile_path(axis: "vertical"), new_admin_profile_path(axis: "horizontal"))
    expect(response.body).to include("Perfis verticais e horizontais da conta atual", "ax-btn--icon")
    expect(Nokogiri::HTML(response.body).css("thead th[scope='col']").size).to eq(7)
  end

  it "renderiza o detalhe tenant-scoped no cabecalho e tabela compartilhados" do
    profile = Profile.create!(tenant: admin.tenant, name: "Gestão #{SecureRandom.hex(4)}", axis: "vertical", position: 650, permissions: {})

    get admin_profile_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", profile.name, "ax-operational-panel", "ax-table__col--w-220")
    expect(response.body).to include("Resumo estrutural do perfil", 'scope="row"')
  end

  it "renderiza permissões em árvore por seção do menu, tela e função" do
    get new_admin_profile_path(axis: "vertical")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    permissions = html.at_css(".prof-permissions")
    sections = Profile.permission_tree_sections
    section_resource_count = sections.count { |section| section[:resource].present? }
    nested_resource_count = Profile::RESOURCES.count do |resource|
      parent = Profile.parent_section_for(resource[:key])
      parent.present? && !Profile.section_resource?(parent)
    end

    expect(permissions["aria-label"]).to include("Permissões por seção do menu")
    expect(permissions.css("article.prof-permission--section").size).to eq(sections.size)
    expect(permissions.css("article.prof-permission--item").size).to eq(Profile::RESOURCES.size - section_resource_count - nested_resource_count)
    expect(permissions.css(".prof-permission--section > details.prof-permission__drawer").size).to eq(sections.size)
    expect(permissions.css(".prof-permission--section > .prof-permission__drawer > .prof-permission__summary").map { |node| node.text.squish }).to include(a_string_including("Produto", "6 menu(s)"), a_string_including("Site público"), a_string_including("Conta"))
    expect(permissions.css(".prof-permission--item .prof-permission__summary").map { |node| node.text.squish }).to include(a_string_including("Imóveis"), a_string_including("Leads"), a_string_including("Bolsão"), a_string_including("Funil"), a_string_including("Dashboard principal"))
    expect(permissions.css(".prof-permission__summary").map { |node| node.text.squish }).to include(a_string_including("Agenda de fotografia", "Seção: Integrações"))
    expect(permissions.css(".prof-permission__primary input[type='checkbox']").size).to eq(Profile::RESOURCES.size)
    expect(permissions.css("details.prof-permission__drawer > .prof-permission__primary").size).to eq(0)
    expect(permissions.css(".prof-permission__action input[type='checkbox']").size).to eq(Profile::RESOURCES.sum { |resource| resource[:actions].size - 1 })
    expect(permissions.css("select[aria-label^='Escopo de ']").size).to eq(Profile::RESOURCES.count { |resource| resource[:scopeable] })
    expect(permissions.css(".prof-menu-includes").map { |node| node.text.squish }).to include(a_string_including("Dashboard SEO"))
    expect(permissions.css(".prof-permission__child-list").map { |node| node.text.squish }).to include(a_string_including("Relatórios de leads"), a_string_including("Locação", "Vendas"), a_string_including("Aba Leads", "Aba Imóveis", "Aba Site público", "Aba Visão geral"))
    expect(permissions.css(".prof-permission__grandchild-list").map { |node| node.text.squish }).to include(a_string_including("Performance dos Corretores", "Performance de Campanhas"))
    expect(permissions.css(".prof-permission__child-items").map { |node| node.text.squish }).to include(a_string_including("Aquisição, gráficos, status e funil", "herda Aba Leads"))
    expect(permissions.css('.prof-permission__children[data-controller="sortable"]').size).to eq(sections.size)
    expect(permissions.css('input[name^="profile[menu_order]"]').map { |node| node["value"] }).to include("dashboard", "imoveis", "leads")
    expect(permissions.css(".prof-permission__drag").size).to eq(Profile::RESOURCES.size - section_resource_count - nested_resource_count)
  end

  it "salva a ordem dos menus enviada pelo formulário do perfil" do
    profile = Profile.create!(tenant: admin.tenant, name: "Ordenável #{SecureRandom.hex(4)}", axis: "vertical", position: 650, permissions: {})

    patch admin_profile_path(profile), params: {
      profile: {
        name: profile.name,
        axis: "vertical",
        active: "1",
        menu_order: {
          product: %w[leads dashboard imoveis fake],
          operation: %w[whatsapp_inbox comercial]
        },
        permissions: {
          admin: "0",
          dashboard: { view: "1" },
          leads: { view: "1", scope: "all" },
          imoveis: { view: "1", scope: "all", locked_fields: [], Profile::HABITATION_SEARCH_STATUSES_PERMISSION_KEY => [] }
        }
      }
    }

    expect(response).to redirect_to(edit_admin_profile_path(profile))
    expect(profile.reload.permissions.fetch(Profile::MENU_ORDER_PERMISSION_KEY)).to include(
      "product" => %w[leads dashboard imoveis],
      "operation" => %w[whatsapp_inbox comercial]
    )
  end
end
