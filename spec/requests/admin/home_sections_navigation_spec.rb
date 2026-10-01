require "rails_helper"

RSpec.describe "Admin home sections navigation", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:sections_tab) { "#{edit_admin_home_setting_path}#home-tab-sections" }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  def create_section!(attrs = {})
    admin.tenant.home_sections.create!(
      { section_type: "featured_properties", title: "Destaques", active: true }.merge(attrs)
    )
  end

  it "volta para a aba Secoes apos ativar/desativar pela aba" do
    section = create_section!(active: false)

    patch toggle_active_admin_home_section_path(section, return_to: "home_settings")

    expect(response).to redirect_to(sections_tab)
    expect(section.reload.active).to be(true)
  end

  it "mantem a listagem apos ativar/desativar sem return_to" do
    section = create_section!(active: true)

    patch toggle_active_admin_home_section_path(section)

    expect(response).to redirect_to(admin_home_sections_path)
    expect(section.reload.active).to be(false)
  end

  it "ignora token de retorno desconhecido" do
    section = create_section!

    patch toggle_active_admin_home_section_path(section, return_to: "http://evil.example.com")

    expect(response).to redirect_to(admin_home_sections_path)
  end

  it "volta para a aba Secoes apos excluir pela aba" do
    section = create_section!

    delete admin_home_section_path(section, return_to: "home_settings")

    expect(response).to redirect_to(sections_tab)
    expect(admin.tenant.home_sections.where(id: section.id)).not_to exist
  end

  it "volta para a aba Secoes apos criar pela aba" do
    post admin_home_sections_path, params: {
      return_to: "home_settings",
      home_section: { content_kind: "blog", title: "Novidades", active: "1" }
    }

    expect(response).to redirect_to(sections_tab)
    expect(admin.tenant.home_sections.find_by(title: "Novidades")).to be_present
  end

  it "volta para a aba Secoes apos atualizar pela aba" do
    section = create_section!

    patch admin_home_section_path(section), params: {
      return_to: "home_settings",
      home_section: { title: "Destaques atualizados" }
    }

    expect(response).to redirect_to(sections_tab)
    expect(section.reload.title).to eq("Destaques atualizados")
  end

  it "oferece Voltar para a aba nas telas de nova secao, edicao e detalhe" do
    section = create_section!

    get new_admin_home_section_path(return_to: "home_settings")
    expect(response.body).to include(sections_tab)
    expect(response.body).to include('name="return_to"')

    get edit_admin_home_section_path(section, return_to: "home_settings")
    expect(response.body).to include(sections_tab)
    expect(response.body).to include('name="return_to"')

    get admin_home_section_path(section, return_to: "home_settings")
    expect(response.body).to include(sections_tab)
  end

  it "lista as secoes na aba sem outro tenant" do
    create_section!(title: "Destaques da conta")
    other = Tenant.create!(name: "Outra home", slug: "outra-home-#{SecureRandom.hex(4)}")
    other.home_sections.create!(section_type: "blog", title: "Blog de outra conta", active: true)

    get edit_admin_home_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Destaques da conta")
    expect(response.body).not_to include("Blog de outra conta")
  end
end
