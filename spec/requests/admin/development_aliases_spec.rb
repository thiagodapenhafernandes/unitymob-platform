require "rails_helper"

RSpec.describe "Admin::DevelopmentAliases", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:development) { create(:habitation, tenant: admin.tenant, tipo: "Empreendimento", nome_empreendimento: "Residencial Parque") }
  let(:stream_headers) { { "Accept" => "text/vnd.turbo-stream.html", "X-CSRF-Token" => token } }
  let(:token) do
    get edit_admin_property_setting_path
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content").to_s
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "cria e atualiza apenas a lista e modal, sem substituir configurações pendentes" do
    post admin_development_aliases_path, params: { development_id: development.id, names: "Reserva Parque; Parque Reserva" }, headers: stream_headers
    expect(response).to have_http_status(:ok)
    expect(DevelopmentAlias.where(tenant: admin.tenant).count).to eq(2)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("turbo-stream").map { |item| item["target"] }).to eq(%w[development-alias-list newDevelopmentAliasModal])
    expect(response.body).to include("Reserva Parque")
    expect(response.body).not_to include('data-ax-modal-open-value="true"')
  end

  it "preserva nomes e empreendimento no modal quando a validação falha e reverte o lote" do
    names = "Válido;#{'a' * 161}"
    post admin_development_aliases_path, params: { development_id: development.id, names: names }, headers: stream_headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(DevelopmentAlias.where(tenant: admin.tenant).count).to eq(0)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("turbo-stream")["target"]).to eq("development-alias-form")
    expect(doc.at_css('textarea[name="names"]').text.strip).to eq(names)
    expect(doc.at_css('select[name="development_id"] option[selected]')["value"]).to eq(development.id.to_s)
    expect(doc.at_css('[role="alert"]')).to be_present
  end

  it "retorna erro contextual quando os dados estão vazios" do
    post admin_development_aliases_path, params: { names: "; ;" }, headers: stream_headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Selecione um empreendimento")
  end

  it "exclui atualizando apenas a lista" do
    record = DevelopmentAlias.create!(tenant: admin.tenant, development: development, name: "Parque")
    delete admin_development_alias_path(record), headers: stream_headers
    expect(response).to have_http_status(:ok)
    expect(DevelopmentAlias.exists?(record.id)).to be(false)
    expect(Nokogiri::HTML(response.body).css("turbo-stream").map { |item| item["target"] }).to eq(["development-alias-list"])
  end

  it "mantém o fallback HTML na subaba correta" do
    post admin_development_aliases_path, params: { authenticity_token: token, development_id: development.id, names: "Parque" }
    expect(response).to redirect_to(edit_admin_property_setting_path(anchor: "property-settings-ai-aliases"))
  end

  it "mostra o modal e preserva entrada no fallback HTML inválido" do
    post admin_development_aliases_path, params: { authenticity_token: token, development_id: development.id, names: "a" * 161 }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('data-ax-modal-open-value="true"')
  end

  it "recusa empreendimento de outra conta" do
    other = Tenant.create!(name: "Outra conta", slug: "aliases-#{SecureRandom.hex(6)}")
    foreign = create(:habitation, tenant: other, tipo: "Empreendimento")
    post admin_development_aliases_path, params: { development_id: foreign.id, names: "Invasão" }, headers: stream_headers
    expect(response).to have_http_status(:not_found)
    expect(DevelopmentAlias.where(tenant: other)).to be_empty
  end

  it "recusa excluir nomes de outra conta" do
    other = Tenant.create!(name: "Outra conta", slug: "aliases-#{SecureRandom.hex(6)}")
    foreign = create(:habitation, tenant: other, tipo: "Empreendimento")
    record = DevelopmentAlias.create!(tenant: other, development: foreign, name: "Outro")
    delete admin_development_alias_path(record), headers: stream_headers
    expect(response).to have_http_status(:not_found)
    expect(DevelopmentAlias.exists?(record.id)).to be(true)
  end
end
