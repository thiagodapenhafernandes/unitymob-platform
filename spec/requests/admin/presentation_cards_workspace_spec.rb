require "rails_helper"

RSpec.describe "Admin::PresentationCards workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "presentation-workspace-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza listagem, cadastro e edicao no cabecalho compartilhado" do
    card = PresentationCard.create!(
      tenant: admin.tenant,
      admin_user: admin,
      label: "Locação",
      greeting: "Olá, eu cuido do seu atendimento.",
      active: true
    )

    get admin_presentation_cards_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Cartões de apresentação", "Novo cartão")
    index = Nokogiri::HTML(response.body)
    expect(index.css("table.ax-table caption").map(&:text)).to include(
      "Template de apresentação disponível para toda a conta",
      "Cartões pessoais de #{admin.name}"
    )
    expect(index.css('table.ax-table th[scope="col"]').size).to eq(9)
    expect(index.at_css(%([aria-label="Editar cartão #{card.label}"]))).to be_present
    expect(index.at_css(%([aria-label="Excluir cartão #{card.label}"]))).to be_present

    get new_admin_presentation_card_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Novo cartão de apresentação")
    new_form = Nokogiri::HTML(response.body)
    expect(new_form.at_css('.ax-field input[name="presentation_card[label]"]')).to be_present
    expect(new_form.at_css('.ax-field textarea[name="presentation_card[greeting]"]')).to be_present
    expect(new_form.at_css(".ax-error-summary")).to be_nil

    get edit_admin_presentation_card_path(card)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Editar cartão: #{card.label}")
  end

  it "cria, atualiza e exclui somente cartoes pessoais do usuario autenticado" do
    post admin_presentation_cards_path, params: {
      presentation_card: {
        label: "Alto padrão",
        greeting: "Olá! Atendo imóveis de alto padrão.",
        use_photo: "1",
        active: "1"
      }
    }

    expect(response).to redirect_to(admin_presentation_cards_path)
    card = admin.presentation_cards.personal.find_by!(label: "Alto padrão")
    expect(card).to have_attributes(
      tenant_id: admin.tenant_id,
      greeting: "Olá! Atendo imóveis de alto padrão.",
      use_photo: true,
      active: true,
      system: false
    )

    patch admin_presentation_card_path(card), params: {
      presentation_card: { label: "Venda premium", greeting: "Nova saudação", use_photo: "0", active: "1" }
    }

    expect(response).to redirect_to(admin_presentation_cards_path)
    expect(card.reload).to have_attributes(label: "Venda premium", greeting: "Nova saudação", use_photo: false)

    expect do
      delete admin_presentation_card_path(card)
    end.to change { admin.presentation_cards.personal.count }.by(-1)
    expect(response).to redirect_to(admin_presentation_cards_path)
  end

  it "não lista nem permite alterar cartão de outro tenant" do
    other_tenant = Tenant.create!(name: "Outra conta de cartões #{SecureRandom.hex(3)}", slug: "outra-conta-cartoes-#{SecureRandom.hex(4)}")
    other_user = create(:admin_user, tenant: other_tenant, email: "other-card-#{SecureRandom.hex(4)}@example.com")
    foreign_card = PresentationCard.create!(
      tenant: other_tenant,
      admin_user: other_user,
      label: "Cartão externo",
      greeting: "Conteúdo externo",
      active: true
    )

    get admin_presentation_cards_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Cartão externo", "Conteúdo externo")

    patch admin_presentation_card_path(foreign_card), params: {
      presentation_card: { label: "Tentativa cruzada", greeting: "Não pode", active: "1" }
    }

    expect(response).to redirect_to(admin_presentation_cards_path)
    expect(foreign_card.reload).to have_attributes(label: "Cartão externo", greeting: "Conteúdo externo")
  end

  it "renderiza erros por meio do resumo compartilhado" do
    post admin_presentation_cards_path, params: {
      presentation_card: { label: "", greeting: "", use_photo: "1", active: "1" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".ax-form-error-summary[role='alert']")).to be_present
    expect(html.at_css('input[name="presentation_card[label]"]')).to be_present
    expect(html.at_css('textarea[name="presentation_card[greeting]"]')).to be_present
  end
end
