require "rails_helper"

RSpec.describe "Calendário administrativo da diária", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "tenant_owner")) }
  let(:property) { create(:habitation, tenant: tenant, status: "Diária") }

  before do
    host! "localhost"
    ActionController::Base.allow_forgery_protection = false
    sign_in owner
  end

  def block_dates(property = self.property, extra = {})
    post admin_habitation_availability_blocks_path(property.id), params: {
      habitation_availability_block: { starts_on: "2026-12-20", ends_on: "2026-12-25" }.merge(extra)
    }
  end

  it "abre por botão sem submeter o imóvel e mantém o modal fora do formulário" do
    get edit_admin_habitation_path(property)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    trigger = doc.at_css('button[data-ax-modal-open="#habitationAvailabilityModal"]')
    expect(trigger['type']).to eq('button')
    modal = doc.at_css('#habitationAvailabilityModal')
    expect(modal).to be_present
    expect(modal.ancestors('main, form')).to be_empty
    expect(modal.at_css('a[target="_blank"]')['href']).to eq(admin_habitation_availability_blocks_path(property.id))
  end

  it "carrega o modal pelo servidor sem remover a página legada" do
    get admin_habitation_availability_blocks_path(property.id, modal: "1")
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("turbo-frame#availability_modal_habitation_#{property.id}")).to be_present
    expect(doc.at_css("[data-controller='ax-date-range']")).to be_present
    expect(doc.css(".ax-date-range__day")).not_to be_empty
    expect(response.body).not_to include("<!DOCTYPE", "<html")
    expect(doc.at_css("input[name='modal']")['value']).to eq("1")
    get admin_habitation_availability_blocks_path(property.id)
    expect(response.body).to include("Data final (inclusive)", "Bloquear período", "ax-mobile-detail-header")
    expect(response.body).not_to include('data-controller="ax-date-range"')
  end

  it "salva, rejeita sobreposição e libera dentro do frame do modal" do
    path = admin_habitation_availability_blocks_path(property.id)
    dates = { starts_on: "2026-12-20", ends_on: "2026-12-25" }
    post path, params: { modal: "1", habitation_availability_block: dates }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(response.body).to include('data-controller="ax-date-range"', "Período bloqueado.")
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("button[data-date='2026-12-25'][disabled]")).to be_present
    expect(doc.at_css("form[method='post'][data-turbo-frame='availability_modal_habitation_#{property.id}']")).to be_present

    expect { post path, params: { modal: "1", month: "2026-12", habitation_availability_block: dates } }.not_to change(HabitationAvailabilityBlock, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Já existe um bloqueio", 'data-controller="ax-date-range"')
    expect(Nokogiri::HTML(response.body).at_css("input[name='habitation_availability_block[starts_on]']")['value']).to eq("2026-12-20")

    delete admin_habitation_availability_block_path(property.id, property.availability_blocks.first, modal: "1", month: "2026-12")
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(response.body).to include("Período liberado.", 'data-controller="ax-date-range"')
    expect(property.availability_blocks).to be_empty
  end

  it "troca só o mês, preservando o formulário do período no modal" do
    get admin_habitation_availability_blocks_path(property.id, modal: "1", calendar: "1", month: "2028-02")
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("turbo-frame#availability_picker_habitation_#{property.id}")).to be_present
    expect(doc.at_css("button[data-date='2028-02-29']")).to be_present
    expect(doc.at_css("input[name='habitation_availability_block[starts_on]']")).to be_nil
    expect(doc.css('nav a').map { |a| a['href'] }).to all(include('calendar=1', 'modal=1'))
    expect(doc.css('nav a').map { |a| a['data-admin-navigation-ignore'] }).to all(eq('true'))
  end

  it "bloqueia, exibe e libera um período com header mobile e formulário padrão" do
    expect { block_dates }.to change(HabitationAvailabilityBlock, :count).by(1)
    expect(response).to have_http_status(:redirect)
    get admin_habitation_availability_blocks_path(property.id, month: "2026-12")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-mobile-detail-header", "Data final (inclusive)", "20/12/2026")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('td.public-theme-availability-calendar__day--blocked time[datetime="2026-12-25"]')).to be_present
    delete admin_habitation_availability_block_path(property.id, property.availability_blocks.first)
    expect(property.availability_blocks.count).to eq(0)
  end

  it "rejeita erro e sobreposição sem registro parcial" do
    block_dates
    expect { block_dates }.not_to change(HabitationAvailabilityBlock, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Já existe um bloqueio")
    block_dates(property, ends_on: "2026-12-19")
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "ignora tenant e imóvel forjados no corpo da requisição" do
    other = create(:habitation, status: "Diária")
    block_dates(property, tenant_id: 0, habitation_id: other.id)
    expect(property.availability_blocks.first.tenant_id).to eq(tenant.id)
    expect(other.availability_blocks).to be_empty
  end

  it "não acessa outra conta nem libera blocos de outro imóvel" do
    other = Tenant.create!(name: "Outra disponibilidade", slug: "outra-disponibilidade-#{SecureRandom.hex(3)}")
    foreign = create(:habitation, tenant: other, status: "Diária")
    block_dates(foreign)
    expect(response).to have_http_status(:not_found)
  end

  it "não libera um bloco que pertence a outro imóvel da conta" do
    other_property = create(:habitation, tenant: tenant, status: "Diária")
    block = other_property.availability_blocks.create!(tenant: tenant, starts_on: "2026-12-20", ends_on: "2026-12-25")
    delete admin_habitation_availability_block_path(property.id, block.id)
    expect(response).to have_http_status(:not_found)
    expect(block.reload).to be_persisted
  end

  it "recusa imóvel sem diária e corretor sem escopo sobre o imóvel" do
    property.update!(status: "Venda")
    get admin_habitation_availability_blocks_path(property.id)
    expect(response).to have_http_status(:not_found)
    property.update!(status: "Diária")
    sign_out owner
    agent = create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "agent"))
    sign_in agent
    block_dates
    expect(response).not_to have_http_status(:ok)
    expect(property.availability_blocks).to be_empty
  end

  it "permite ao corretor editor bloquear o próprio imóvel e recusa um imóvel alheio" do
    profile = tenant.profiles.find_by!(key: "agent")
    profile.update!(permissions: { "imoveis" => { "view" => true, "edit" => true, "scope" => "own" } })
    agent = create(:admin_user, tenant: tenant, profile: profile)
    property.update!(admin_user: agent)
    sign_out owner
    sign_in agent
    block_dates
    expect(response).to have_http_status(:redirect)
    expect(property.availability_blocks.count).to eq(1)
    foreign = create(:habitation, tenant: tenant, status: "Diária", admin_user: owner)
    block_dates(foreign)
    expect(response).to have_http_status(:forbidden)
    expect(foreign.availability_blocks).to be_empty
  end


  it "funciona também na administração de outra conta" do
    other = Tenant.create!(name: "Outra diária", slug: "outra-diaria-calendar-#{SecureRandom.hex(3)}")
    other_owner = create(:admin_user, tenant: other, profile: other.profiles.find_by!(key: "tenant_owner"))
    other_property = create(:habitation, tenant: other, status: "Diária")
    sign_out owner
    sign_in other_owner
    block_dates(other_property)
    expect(response).to have_http_status(:redirect)
    expect(other_property.availability_blocks.first.tenant_id).to eq(other.id)
  end

end
