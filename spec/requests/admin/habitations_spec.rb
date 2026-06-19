require "rails_helper"
require "tempfile"

RSpec.describe "Admin::Habitations", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "separa captações restritas da listagem geral de imóveis" do
    draft = create(:habitation, :broker_intake, admin_user: admin, codigo: "DRAFT-#{SecureRandom.hex(6)}", titulo_anuncio: "Captação em rascunho")
    submitted = create(:habitation, :broker_intake, admin_user: admin, codigo: "REV-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review", titulo_anuncio: "Captação finalizada")
    approved = create(:habitation, :broker_intake, admin_user: admin, codigo: "APP-#{SecureRandom.hex(6)}", intake_status: "admin_approved", titulo_anuncio: "Captação aprovada")
    internal = create(:habitation, :broker_intake, admin_user: admin, codigo: "INT-#{SecureRandom.hex(6)}", intake_status: "internal", titulo_anuncio: "Captação interna")
    published = create(:habitation, :broker_intake, admin_user: admin, codigo: "PUB-#{SecureRandom.hex(6)}", intake_status: "published", titulo_anuncio: "Captação publicada")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pendente de revisão")
    expect(response.body).to include(internal.titulo_anuncio)
    expect(response.body).to include(published.titulo_anuncio)
    expect(response.body).not_to include(submitted.titulo_anuncio)
    expect(response.body).not_to include(approved.titulo_anuncio)
    expect(response.body).not_to include(draft.titulo_anuncio)

    get admin_habitations_path(intake_review: "pending", ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(submitted.titulo_anuncio)
    expect(response.body).to include(approved.titulo_anuncio)
    expect(response.body).not_to include(draft.titulo_anuncio)
    expect(response.body).not_to include(internal.titulo_anuncio)
    expect(response.body).not_to include(published.titulo_anuncio)
  end

  it "mostra para o corretor somente suas captações aguardando aceite" do
    broker_profile = Profile.create!(
      name: "Corretor revisão #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    luciana = create(:admin_user, profile: broker_profile, name: "Luciana Indalécio")
    patricia = create(:admin_user, profile: broker_profile, name: "Patrícia Paula")
    own_waiting = create(:habitation, :broker_intake, admin_user: luciana, codigo: "OWN-REV-#{SecureRandom.hex(6)}", intake_status: "admin_approved", titulo_anuncio: "Aguardando aceite Luciana")
    other_waiting = create(:habitation, :broker_intake, admin_user: patricia, codigo: "OTH-REV-#{SecureRandom.hex(6)}", intake_status: "admin_approved", titulo_anuncio: "Aguardando aceite Patrícia")
    submitted = create(:habitation, :broker_intake, admin_user: luciana, codigo: "SUB-REV-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review", titulo_anuncio: "Em revisão administrativa Luciana")

    sign_in luciana
    get admin_habitations_path(intake_review: "pending", ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_waiting.titulo_anuncio)
    expect(response.body).not_to include(other_waiting.titulo_anuncio)
    expect(response.body).not_to include(submitted.titulo_anuncio)
    expect(response.body).to include("Aguardando aceite do corretor")
  end

  it "exibe ações de ficha de papel no novo cadastro administrativo" do
    get new_admin_habitation_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('novalidate="novalidate"')
    expect(response.body).to include("Enviar para corretor")
    expect(response.body).to include("Salvar Interno")
    expect(response.body).to include("Salvar")
    expect(response.body).to include("Salvar e sair")
  end

  it "mantém ações de revisão administrativa vinculadas ao formulário principal" do
    habitation = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      intake_status: "submitted_for_admin_review",
      codigo: "REV-ACTION-#{SecureRandom.hex(6)}"
    )

    return_path = admin_habitations_path(ownership: "all", q: habitation.codigo)

    get edit_admin_habitation_path(habitation, return_to: return_path)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin_habitation_form"')
    expect(response.body).to include('data-turbo="false"')
    expect(response.body).to include('name="release_to_broker_after_save"')
    expect(response.body).to include('name="save_internal_after_save"')
    expect(response.body.scan('form="admin_habitation_form"').size).to be >= 4
  end

  it "não inclui ações de exclusão de anexos como método do formulário principal" do
    habitation = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      intake_status: "submitted_for_admin_review",
      codigo: "REV-DOC-#{SecureRandom.hex(6)}"
    )
    habitation.fichas_cadastro.attach(
      io: StringIO.new("ficha"),
      filename: "ficha.txt",
      content_type: "text/plain"
    )
    habitation.autorizacoes_venda.attach(
      io: StringIO.new("autorizacao"),
      filename: "autorizacao.txt",
      content_type: "text/plain"
    )

    return_path = admin_habitations_path(ownership: "all", q: habitation.codigo)

    get edit_admin_habitation_path(habitation, return_to: return_path)

    expect(response).to have_http_status(:ok)
    form_markup = response.body[/<form[^>]*id="admin_habitation_form"[\s\S]*?<\/form>/]
    expect(form_markup).to be_present
    expect(form_markup.scan("<form").size).to eq(1)
    expect(form_markup).not_to include('name="_method" value="delete"')

    ficha_attachment = habitation.fichas_cadastro.attachments.first
    authorization_attachment = habitation.autorizacoes_venda.attachments.first
    expect(response.body).to include(%(form="purge_attachment_#{ficha_attachment.id}"))
    expect(response.body).to include(%(form="purge_attachment_#{authorization_attachment.id}"))
    expect(response.body).to include(%(id="purge_attachment_#{ficha_attachment.id}"))
    expect(response.body).to include(%(id="purge_attachment_#{authorization_attachment.id}"))
    expect(response.body).to include('name="_method" value="delete"')
    [ficha_attachment, authorization_attachment].each do |attachment|
      purge_form_markup = response.body[/<form[^>]*id="purge_attachment_#{attachment.id}"[\s\S]*?<\/form>/]
      expect(purge_form_markup).to be_present
      expect(purge_form_markup).to include('name="return_to"')
      expect(purge_form_markup).to include(%(value="#{CGI.escapeHTML(return_path)}"))
    end
    expect(response.body).to include(purge_attachment_admin_habitation_path(habitation, association: "fichas_cadastro", attachment_id: ficha_attachment.id))
    expect(response.body).to include(purge_attachment_admin_habitation_path(habitation, association: "autorizacoes_venda", attachment_id: authorization_attachment.id))
  end

  it "exibe no topo o captador vindo dos responsáveis e agenciamento" do
    captador = create(:admin_user, name: "Luciana Indalécio")
    habitation = create(
      :habitation,
      admin_user: nil,
      codigo: "CAP-TOP-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel com captador por vínculo"
    )
    habitation.broker_assignments.create!(admin_user: captador, role: "captador")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Captador")
    expect(response.body).to include("Luciana Indalécio")
    expect(response.body).to include("Captador responsável:")
    expect(response.body).not_to include("Corretor responsável:")
  end

  it "exibe nome do empreendimento no cadastro do tipo empreendimento" do
    development = create(
      :habitation,
      tipo: "Empreendimento",
      categoria: "Empreendimento",
      codigo: "54",
      nome_empreendimento: "Empreendimento Centro Cod. 54"
    )

    get edit_admin_habitation_path(development)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pesquisar por código/referência")
    expect(response.body).to include("Nome do empreendimento:")
    expect(response.body).to include("Empreendimento Centro Cod. 54")
  end

  it "abre o cadastro pesquisando pelo código" do
    development = create(
      :habitation,
      tipo: "Empreendimento",
      categoria: "Empreendimento",
      codigo: "54",
      nome_empreendimento: "Empreendimento Centro Cod. 54"
    )

    get search_by_code_admin_habitations_path(codigo: "54")

    expect(response).to redirect_to(edit_admin_habitation_path(development))
  end

  it "filtra somente imóveis do DWV na listagem" do
    dwv_property = create(
      :habitation,
      codigo: "DWV-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel vindo do DWV",
      imovel_dwv: "Sim"
    )
    vista_property = create(
      :habitation,
      codigo: "VISTA-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel vindo da Vista",
      imovel_dwv: "Nao"
    )

    get admin_habitations_path(somente_dwv: "1")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Somente imóveis do DWV")
    expect(response.body).to include(dwv_property.titulo_anuncio)
    expect(response.body).not_to include(vista_property.titulo_anuncio)
  end

  it "não inclui imóveis apenas vinculados como corretor secundário em Meus imóveis" do
    broker_profile = Profile.create!(
      name: "Corretor ownership #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    luciana = create(:admin_user, profile: broker_profile, name: "Luciana Indalécio")
    patricia = create(:admin_user, profile: broker_profile, name: "Patrícia Paula")
    own_property = create(:habitation, admin_user: luciana, codigo: "OWN-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel da Luciana")
    secondary_property = create(:habitation, admin_user: patricia, codigo: "SEC-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel da Patrícia")
    secondary_property.broker_assignments.create!(admin_user: luciana, role: "captador")

    sign_in luciana
    get admin_habitations_path(ownership: "mine")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_property.titulo_anuncio)
    expect(response.body).not_to include(secondary_property.titulo_anuncio)
  end

  it "abre imóvel de Todos no detalhe interno para corretor sem permissão de edição" do
    broker_profile = Profile.create!(
      name: "Corretor todos #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    vera = create(:admin_user, profile: broker_profile, name: "Vera Corretora")
    other_broker = create(:admin_user, profile: broker_profile, name: "Outro Corretor")
    other_property = create(
      :habitation,
      admin_user: other_broker,
      codigo: "TODOS-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel de todos para consulta",
      proprietario: "Proprietário Restrito"
    )

    sign_in vera
    get admin_habitations_path(ownership: "all", q: other_property.codigo)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(other_property.titulo_anuncio)
    expect(response.body).to include("Captador:")
    expect(response.body).to include(other_broker.name)
    card = Nokogiri::HTML(response.body).css(".property-card-horizontal").find { |node| node.text.include?(other_property.codigo) }
    expect(card["style"].to_s).not_to include("height: 240px")
    expect(response.body).to include(CGI.escapeHTML(admin_habitation_path(other_property, return_to: request.fullpath)))
    expect(response.body).not_to include(%(data-clickable-card-url-value="#{CGI.escapeHTML(habitation_path(other_property))}"))

    get admin_habitation_path(other_property, return_to: admin_habitations_path(ownership: "all", q: other_property.codigo))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Informações principais")
    expect(response.body).to include(other_property.titulo_anuncio)
    expect(response.body).to include("Captador")
    expect(response.body).to include(other_broker.name)
    expect(response.body).not_to include("Proprietário</div>")
    expect(response.body).not_to include("Proprietário Restrito")

    get edit_admin_habitation_path(other_property)

    expect(response).to redirect_to(admin_habitations_path)

    patch admin_habitation_path(other_property), params: {
      habitation: {
        status: "Aluguel",
        valor_venda_formatted: "123.000,00",
        titulo_anuncio: "Tentativa de alteração por outro corretor"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(other_property.reload).to have_attributes(
      status: "Venda",
      titulo_anuncio: "Imóvel de todos para consulta"
    )
    expect(other_property.valor_venda_cents).not_to eq(123_000_00)
  end

  it "abre imóvel próprio na aba Todos em visualização interna, não em edição" do
    broker_profile = Profile.create!(
      name: "Corretor todos proprio #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    vera = create(:admin_user, profile: broker_profile, name: "Vera Corretora")
    own_property = create(
      :habitation,
      admin_user: vera,
      codigo: "TODOS-PROP-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel próprio na aba todos"
    )

    sign_in vera
    get admin_habitations_path(ownership: "all", q: own_property.codigo)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_property.titulo_anuncio)
    expect(response.body).to include(CGI.escapeHTML(admin_habitation_path(own_property, return_to: request.fullpath)))
    expect(response.body).to include(CGI.escapeHTML(edit_admin_habitation_path(own_property, return_to: request.fullpath)))
  end

  it "permite que corretor filtre imóveis por outro corretor na aba Todos" do
    broker_profile = Profile.create!(
      name: "Corretor filtro #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    luciana = create(:admin_user, profile: broker_profile, name: "Luciana Filtro")
    patricia = create(:admin_user, profile: broker_profile, name: "Patrícia Filtro")
    own_property = create(
      :habitation,
      admin_user: luciana,
      codigo: "FILTRO-OWN-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel da Luciana no filtro"
    )
    other_property = create(
      :habitation,
      admin_user: patricia,
      codigo: "FILTRO-OTHER-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel da Patrícia no filtro"
    )

    sign_in luciana
    get admin_habitations_path(ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="corretor_id"')
    expect(response.body).to include("Patrícia Filtro")
    expect(response.body).not_to include('name="proprietor_id"')

    get admin_habitations_path(ownership: "all", corretor_id: patricia.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(other_property.titulo_anuncio)
    expect(response.body).not_to include(own_property.titulo_anuncio)
  end

  it "combina status, categoria e Frente Mar sem trazer imóveis incompatíveis" do
    matching = create(
      :habitation,
      codigo: "FILTRO-OK-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento venda frente mar correto",
      status: "Venda",
      categoria: "Apartamento",
      frente_mar_avenida_atlantica_flag: true
    )
    wrong_category = create(
      :habitation,
      codigo: "FILTRO-CASA-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Casa frente mar fora do filtro",
      status: "Venda",
      categoria: "Casa",
      frente_mar_avenida_atlantica_flag: true
    )
    wrong_status = create(
      :habitation,
      codigo: "FILTRO-ALUGUEL-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento aluguel frente mar fora do filtro",
      status: "Aluguel",
      categoria: "Apartamento",
      frente_mar_avenida_atlantica_flag: true
    )
    vista_only = create(
      :habitation,
      codigo: "FILTRO-VISTA-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento vista mar não é frente mar",
      status: "Venda",
      categoria: "Apartamento",
      vista_frente_mar_flag: true,
      caracteristicas: ["Vista Mar"]
    )

    get admin_habitations_path(
      ownership: "all",
      status: "Venda",
      categoria: "Apartamento",
      amenities: ["Frente Mar"]
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.titulo_anuncio)
    expect(response.body).not_to include(wrong_category.titulo_anuncio)
    expect(response.body).not_to include(wrong_status.titulo_anuncio)
    expect(response.body).not_to include(vista_only.titulo_anuncio)
  end

  it "aplica o pill Frente Mar com a mesma regra estrita do checkbox" do
    matching = create(
      :habitation,
      codigo: "PILL-FRENTE-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento pill frente mar correto",
      status: "Venda",
      categoria: "Apartamento Garden",
      caracteristicas: ["Frente Mar"]
    )
    vista_only = create(
      :habitation,
      codigo: "PILL-VISTA-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento pill vista mar fora",
      status: "Venda",
      categoria: "Apartamento",
      vista_frente_mar_flag: true,
      caracteristicas: ["Vista Mar"]
    )

    get admin_habitations_path(
      ownership: "all",
      status: "Venda",
      categoria: "Apartamento",
      scope: "frente_mar"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.titulo_anuncio)
    expect(response.body).not_to include(vista_only.titulo_anuncio)
  end

  it "filtra corretor também pelo responsável principal do imóvel" do
    admin = create(:admin_user, :admin)
    broker = create(:admin_user, name: "Corretor Principal #{SecureRandom.hex(4)}")
    other_broker = create(:admin_user, name: "Outro Corretor #{SecureRandom.hex(4)}")
    owned_by_broker = create(
      :habitation,
      admin_user: broker,
      codigo: "CORRETOR-OK-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel do corretor principal"
    )
    owned_by_other = create(
      :habitation,
      admin_user: other_broker,
      codigo: "CORRETOR-OUTRO-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel de outro corretor"
    )

    sign_in admin
    get admin_habitations_path(ownership: "all", corretor_id: broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(owned_by_broker.titulo_anuncio)
    expect(response.body).not_to include(owned_by_other.titulo_anuncio)
  end

  it "ordena imóveis novos no topo quando a data de cadastro CRM está vazia" do
    old_property = create(:habitation, codigo: "OLD-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel antigo", data_cadastro_crm: 2.days.ago)
    new_property = create(:habitation, codigo: "NEW-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel novo")
    new_property.update_column(:data_cadastro_crm, nil)

    get admin_habitations_path(sort: "data_cadastro_crm", direction: "desc")

    expect(response).to have_http_status(:ok)
    expect(response.body.index(new_property.titulo_anuncio)).to be < response.body.index(old_property.titulo_anuncio)
  end

  it "filtra por rua considerando endereço estruturado e legado" do
    structured = create(:habitation, codigo: "RUA-EST-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel Rua Estruturada")
    structured.create_address!(
      tipo_endereco: "Rua",
      logradouro: "Central Norte",
      numero: "10",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    legacy = create(
      :habitation,
      codigo: "RUA-LEG-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel Rua Legada",
      endereco: "Avenida Atlântica, 500"
    )

    get admin_habitations_path(logradouro: "Central Norte")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(structured.titulo_anuncio)
    expect(response.body).not_to include(legacy.titulo_anuncio)

    get admin_habitations_path(logradouro: "Atlântica")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(legacy.titulo_anuncio)
    expect(response.body).not_to include(structured.titulo_anuncio)
  end

  it "filtra por múltiplos bairros no catálogo" do
    centro = create(:habitation, codigo: "BAIRRO-CENTRO-#{SecureRandom.hex(4)}", titulo_anuncio: "Imóvel bairro Centro", bairro: "Centro")
    barra = create(:habitation, codigo: "BAIRRO-BARRA-#{SecureRandom.hex(4)}", titulo_anuncio: "Imóvel bairro Barra Sul", bairro: "Barra Sul")
    outro = create(:habitation, codigo: "BAIRRO-OUTRO-#{SecureRandom.hex(4)}", titulo_anuncio: "Imóvel bairro Outro", bairro: "Nações")

    get admin_habitations_path(bairro: ["Centro", "Barra Sul"])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(centro.titulo_anuncio)
    expect(response.body).to include(barra.titulo_anuncio)
    expect(response.body).not_to include(outro.titulo_anuncio)
    expect(response.body).to include("Bairro: Centro, Barra Sul")
  end

  it "inclui nome de prédio sem cadastro de empreendimento no filtro de imóveis" do
    standalone_unit = create(
      :habitation,
      codigo: "PREDIO-UNIT-#{SecureRandom.hex(6)}",
      tipo: "Unitário",
      codigo_empreendimento: nil,
      nome_empreendimento: "Residencial Sem Cadastro",
      titulo_anuncio: "Unidade com prédio direto"
    )
    other_property = create(
      :habitation,
      codigo: "PREDIO-OTHER-#{SecureRandom.hex(6)}",
      tipo: "Unitário",
      codigo_empreendimento: nil,
      nome_empreendimento: "Outro Prédio",
      titulo_anuncio: "Outro imóvel"
    )

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Residencial Sem Cadastro")

    get admin_habitations_path(empreendimento_codigo: "Residencial Sem Cadastro")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(standalone_unit.titulo_anuncio)
    expect(response.body).not_to include(other_property.titulo_anuncio)
  end

  it "filtra empreendimento por corretor sem erro de distinct com ordenação" do
    broker = create(:admin_user, name: "Laudi Cardoso")
    create(:habitation, codigo: "183", tipo: "Empreendimento", nome_empreendimento: "Residencial 183")
    matching = create(
      :habitation,
      codigo: "EMP-BROKER-#{SecureRandom.hex(6)}",
      codigo_empreendimento: "183",
      titulo_anuncio: "Imóvel do corretor filtrado"
    )
    other_property = create(
      :habitation,
      codigo: "EMP-OTHER-#{SecureRandom.hex(6)}",
      codigo_empreendimento: "183",
      titulo_anuncio: "Imóvel de outro corretor"
    )
    matching.broker_assignments.create!(admin_user: broker, role: "captador")

    get admin_habitations_path(empreendimento_codigo: "183", corretor_id: broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.titulo_anuncio)
    expect(response.body).not_to include(other_property.titulo_anuncio)
  end

  it "preserva filtros da listagem ao editar e salvar saindo" do
    habitation = create(:habitation, codigo: "RET-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel com retorno")
    habitation.create_address!(
      logradouro: "Rua Retorno",
      numero: "123",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    return_path = admin_habitations_path(q: habitation.codigo, status: habitation.status)

    get return_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escape(return_path))

    get edit_admin_habitation_path(habitation, return_to: return_path)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ERB::Util.html_escape(return_path))

    patch admin_habitation_path(habitation), params: {
      return_to: return_path,
      save_navigation: "exit",
      habitation: {
        titulo_anuncio: "Imóvel com retorno atualizado",
        address_attributes: {
          id: habitation.address.id,
          logradouro: "Rua Retorno",
          numero: "123",
          bairro: "Centro",
          cidade: "Balneário Camboriú",
          uf: "SC"
        }
      }
    }

    expect(response).to redirect_to(return_path)
  end

  it "remove filtros vazios do retorno para manter a URL do cadastro enxuta" do
    habitation = create(:habitation, codigo: "RET-LIMPO-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel com retorno limpo")
    noisy_return_path = "/admin/habitations?ownership=all&q=#{CGI.escape(habitation.codigo)}&bairro=&status=&dorms%5B%5D=&vagas%5B%5D="
    clean_return_path = admin_habitations_path(ownership: "all", q: habitation.codigo)

    get noisy_return_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML(edit_admin_habitation_path(habitation, return_to: clean_return_path)))
    expect(response.body).not_to include(CGI.escapeHTML(edit_admin_habitation_path(habitation, return_to: noisy_return_path)))

    get edit_admin_habitation_path(habitation, return_to: noisy_return_path)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ERB::Util.html_escape(clean_return_path))
    expect(response.body).not_to include(ERB::Util.html_escape(noisy_return_path))
  end

  it "não exibe Netimóveis 2 e Loft na área de portais" do
    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Publicar Netimoveis 2")
    expect(response.body).not_to include("Publicar Loft")
    expect(response.body).not_to include('value="netimoveis_2"')
    expect(response.body).not_to include('value="loft"')
  end

  it "remove Praia Brava Balneário Camboriú da lista de bairros comerciais" do
    create(:habitation, codigo: "BAIRRO-#{SecureRandom.hex(6)}", bairro_comercial: "Praia Brava Balneário Camboriú")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Praia Brava Balneário Camboriú")
  end

  it "marca cards inativos com classe visual cinza" do
    inactive = create(:habitation, codigo: "INATIVO-#{SecureRandom.hex(6)}", status: "Suspenso", titulo_anuncio: "Imóvel inativo")

    get admin_habitations_path(q: inactive.codigo, status: "Suspenso")

    expect(response).to have_http_status(:ok)
    card = Nokogiri::HTML(response.body).css(".property-card-horizontal").find { |node| node.text.include?(inactive.codigo) }
    expect(card["class"]).to include("property-card--inactive")
  end

  it "não marca imóvel ativo fora do site como card cinza" do
    internal = create(:habitation, codigo: "INTERNO-#{SecureRandom.hex(6)}", status: "Aluguel", exibir_no_site_flag: false, titulo_anuncio: "Imóvel interno ativo")

    get admin_habitations_path(q: internal.codigo)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("FORA SITE")
    card = Nokogiri::HTML(response.body).css(".property-card-horizontal").find { |node| node.text.include?(internal.codigo) }
    expect(card["class"]).not_to include("property-card--inactive")
  end

  it "renderiza o catálogo em workspace com sidebar global e filtros no inspector" do
    create(:habitation, codigo: "LAYOUT-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel para layout master detail")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{<aside class="ax-sidebar"})
    expect(response.body).to match(%r{<body class="[^"]*\bax-habitations-workspace\b})
    expect(response.body).not_to match(%r{<body class="[^"]*\badmin-drawer-catalog-layout\b})
    expect(response.body).not_to match(%r{<body class="[^"]*\bax-catalog-layout\b})
    expect(response.body).to include('class="habitations-master-detail-layout" data-controller="habitations-inspector"')
    expect(response.body).to include('class="habitations-detail-pane"')
    expect(response.body).to include('class="habitations-master-pane"')
    expect(response.body).to include("Filtros do catálogo")
    expect(response.body).to include('class="habitations-inspector-rail"')
    expect(response.body).to include('data-action="click-&gt;habitations-inspector#toggle"')
    expect(response.body).not_to include("PROPERTY_QUERY")
    expect(response.body).not_to include(">Inspector<")
  end

  it "mantém o modal de exportação fora do preloader de navegação global" do
    export = admin.habitation_exports.create!(
      status: "completed",
      progress: 100,
      filename: "imoveis_exportacao_teste.csv",
      fields: %w[codigo categoria],
      source_ids: [],
      col_sep: ";",
      record_count: 0
    )
    export.file.attach(io: StringIO.new("Referencia\n"), filename: export.filename, content_type: "text/csv; charset=utf-8")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="habitationsExportModal"')
    expect(response.body.scan('data-admin-navigation-ignore="true"').size).to be >= 2
    expect(response.body).to include('data-turbo="false"')
    expect(response.body).to include('download="imoveis_exportacao_teste.csv"')
    expect(response.body).to include('data-controller="ax-async-download"')
    expect(response.body).to include('data-action="ax-async-download#download"')
  end

  it "inicia a exportação CSV assíncrona e lista o progresso no modal" do
    habitation = create(:habitation, codigo: "ASYNC-CSV-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel para exportação assíncrona")

    expect do
      post export_admin_habitations_path(format: :json),
           params: { fields: %w[codigo categoria], data_format: "csv_semicolon", q: habitation.codigo },
           headers: { "ACCEPT" => "application/json" }
    end.to change(HabitationExport, :count).by(1)
      .and change(DataExportAuditLog, :count).by(1)

    export = HabitationExport.last
    payload = JSON.parse(response.body)

    expect(response).to have_http_status(:ok)
    expect(payload).to include(
      "id" => export.id,
      "filename" => export.filename,
      "status" => "pending",
      "progress" => 0,
      "record_count" => 1,
      "ready" => false
    )
    expect(payload["download_url"]).to be_nil

    get exports_admin_habitations_path(format: :json), headers: { "ACCEPT" => "application/json" }

    list_payload = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(list_payload.fetch("exports").first).to include(
      "id" => export.id,
      "status" => "pending",
      "progress" => 0,
      "record_count" => 1
    )
  end

  it "abre os relatórios de impressão do menu principal" do
    create(:habitation, codigo: "PRINT-#{SecureRandom.hex(6)}", categoria: "Apartamento", titulo_anuncio: "Imóvel residencial para impressão")
    create(:habitation, codigo: "PRINT-#{SecureRandom.hex(6)}", categoria: "Sala Comercial", titulo_anuncio: "Imóvel comercial para impressão")
    create(:habitation, codigo: "PRINT-#{SecureRandom.hex(6)}", categoria: "Terreno", titulo_anuncio: "Terreno para impressão")

    %w[
      photos_sheet
      client_sheet_commercial
      client_sheet_residential
      client_sheet_land
      vitrine_sheet
    ].each do |report_type|
      get print_admin_habitations_path(report_type: report_type, full_print: "1")

      expect(response).to have_http_status(:ok), "esperava abrir o relatório #{report_type}"
      expect(response.body).to include(Admin::HabitationsController::REPORT_TYPES.fetch(report_type).upcase)
    end
  end

  it "salva o imóvel completo e libera a captação para o corretor publicar" do
    intake = create(:habitation, :broker_intake, admin_user: admin, codigo: "REL-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review")
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Central",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    intake.autorizacoes_venda.attach(
      io: StringIO.new("autorizacao"),
      filename: "autorizacao.txt",
      content_type: "text/plain"
    )

    patch admin_habitation_path(intake), params: {
      release_to_broker_after_save: "1",
      habitation: {
        titulo_anuncio: "Casa em Condomínio completa pelo administrativo",
        exibir_no_site_flag: "1"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(intake.reload).to have_attributes(
      intake_status: "admin_approved",
      titulo_anuncio: "Casa em Condomínio completa pelo administrativo",
      exibir_no_site_flag: false,
      admin_reviewed_by_id: admin.id
    )
    expect(intake.admin_reviewed_at).to be_present
  end

  it "não remove autorização existente quando devolve para captador com campo de arquivo vazio" do
    intake = create(:habitation, :broker_intake, admin_user: admin, codigo: "AUTH-KEEP-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review")
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Autorização",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    intake.autorizacoes_venda.attach(
      io: StringIO.new("autorizacao existente"),
      filename: "autorizacao-existente.txt",
      content_type: "text/plain"
    )

    patch admin_habitation_path(intake), params: {
      release_to_broker_after_save: "1",
      habitation: {
        titulo_anuncio: "Casa em Condomínio com autorização preservada",
        autorizacoes_venda: [""]
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(intake.reload).to have_attributes(intake_status: "admin_approved")
    expect(intake.autorizacoes_venda).to be_attached
    expect(intake.autorizacoes_venda.attachments.map { |attachment| attachment.filename.to_s }).to include("autorizacao-existente.txt")
  end

  it "salva autorização nova antes de validar devolução para captador" do
    intake = create(:habitation, :broker_intake, admin_user: admin, codigo: "AUTH-NEW-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review")
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Autorização Nova",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    authorization = Rack::Test::UploadedFile.new(
      StringIO.new("autorizacao nova"),
      "text/plain",
      original_filename: "autorizacao-nova.txt"
    )

    patch admin_habitation_path(intake), params: {
      release_to_broker_after_save: "1",
      habitation: {
        titulo_anuncio: "Casa em Condomínio com autorização nova",
        autorizacoes_venda: ["", authorization]
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(intake.reload).to have_attributes(intake_status: "admin_approved")
    expect(intake.autorizacoes_venda).to be_attached
    expect(intake.autorizacoes_venda.attachments.map { |attachment| attachment.filename.to_s }).to include("autorizacao-nova.txt")
  end

  it "salva captação revisada internamente sem exibir no site" do
    intake = create(:habitation, :broker_intake, admin_user: admin, codigo: "INT-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review")
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Interna",
      numero: "200",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    intake.autorizacoes_venda.attach(
      io: StringIO.new("autorizacao"),
      filename: "autorizacao.txt",
      content_type: "text/plain"
    )

    get edit_admin_habitation_path(intake)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Devolver para captador")
    expect(response.body).to include("Salvar Interno")
    expect(response.body).to include("Salvar e sair")
    expect(response.body).to include("Autorizações de Venda")
    expect(response.body).to include("autorizacao.txt")
    expect(response.body).to include("Adicionar arquivos")

    patch admin_habitation_path(intake), params: {
      save_internal_after_save: "1",
      habitation: {
        titulo_anuncio: "Casa em Condomínio salva internamente",
        exibir_no_site_flag: "1"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(intake.reload).to have_attributes(
      intake_status: "internal",
      titulo_anuncio: "Casa em Condomínio salva internamente",
      exibir_no_site_flag: false,
      admin_reviewed_by_id: admin.id
    )
  end

  it "exibe e atualiza o status separado da captação no cadastro completo" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      codigo: "REV-#{SecureRandom.hex(6)}",
      intake_status: "submitted_for_admin_review"
    )
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Central",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    get edit_admin_habitation_path(intake)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Status da captação")
    expect(response.body).to include("Fluxo separado do status comercial.")

    patch admin_habitation_path(intake), params: {
      habitation: {
        intake_status: "returned_to_broker",
        status: "Venda"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(intake.reload).to have_attributes(
      intake_status: "returned_to_broker",
      status: "Venda",
      exibir_no_site_flag: false,
      admin_reviewed_by_id: admin.id
    )
    expect(intake.admin_reviewed_at).to be_present
  end

  it "exibe região foco como decisão sim ou não no cadastro completo" do
    habitation = create(:habitation, codigo: "FOCO-#{SecureRandom.hex(6)}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Região foco?")
    page = Nokogiri::HTML(response.body)
    options = page.css('select[name="habitation[regiao_foco]"] option').map(&:text)
    expect(options).to include("Sim", "Não")
    expect(options).not_to include("Centro")
  end

  it "exibe telefone do proprietário vinculado quando o imóvel não tem telefone legado" do
    proprietor = create(
      :proprietor,
      name: "Jeanine",
      phone_primary: "47 98868.0402",
      mobile_phone: nil,
      business_phone: nil,
      residential_phone: nil
    )
    habitation = create(
      :habitation,
      proprietor: proprietor,
      proprietario: "Jeanine",
      proprietario_celular: nil,
      proprietario_telefone_comercial: nil,
      proprietario_telefone_residencial: nil
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Jeanine")
    expect(response.body).to include("47 98868.0402")
  end

  it "mantém classificação de fotos visível para o administrativo" do
    habitation = create(:habitation, codigo: "FOTO-ADM-#{SecureRandom.hex(6)}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Classificação das Fotos:")
  end

  it "não remove fotos existentes quando o formulário envia upload vazio" do
    habitation = create(:habitation, codigo: "FOTO-KEEP-#{SecureRandom.hex(6)}", titulo_anuncio: "Título antigo")
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "101",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    habitation.photos.attach(
      io: StringIO.new("foto existente"),
      filename: "existente.jpg",
      content_type: "image/jpeg"
    )

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: "Título sem trocar foto",
        photos: [""]
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload.titulo_anuncio).to eq("Título sem trocar foto")
    expect(habitation.photos.attachments.size).to eq(1)
    expect(habitation.photos.attachments.first.filename.to_s).to eq("existente.jpg")
  end

  it "adiciona novas fotos sem substituir fotos anexadas existentes" do
    habitation = create(:habitation, codigo: "FOTO-APPEND-#{SecureRandom.hex(6)}", titulo_anuncio: "Título antigo")
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "104",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    habitation.photos.attach(
      io: StringIO.new("foto existente"),
      filename: "existente.jpg",
      content_type: "image/jpeg"
    )
    uploaded_photo = Tempfile.new(["nova-foto", ".jpg"])
    uploaded_photo.write("foto nova")
    uploaded_photo.rewind

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: "Título com foto nova",
        photos: [Rack::Test::UploadedFile.new(uploaded_photo.path, "image/jpeg")]
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload.photos.attachments.size).to eq(2)
    expect(habitation.photos.attachments.map { |attachment| attachment.filename.to_s }).to include("existente.jpg")
  ensure
    uploaded_photo&.close
    uploaded_photo&.unlink
  end

  it "adiciona fotos enviadas por direct upload" do
    habitation = create(:habitation, codigo: "FOTO-DIRECT-#{SecureRandom.hex(6)}", titulo_anuncio: "Título antigo")
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "106",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("foto enviada direto"),
      filename: "direct-upload.jpg",
      content_type: "image/jpeg"
    )

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: "Título com direct upload",
        photos: [blob.signed_id]
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload.photos.attachments.size).to eq(1)
    expect(habitation.photos.attachments.first.blob).to eq(blob)
  end

  it "enfileira marca d'água das novas fotos fora da requisição" do
    clear_enqueued_jobs
    habitation = create(:habitation, codigo: "FOTO-WATERMARK-#{SecureRandom.hex(6)}", titulo_anuncio: "Título antigo")
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "107",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    setting = PropertySetting.instance
    setting.watermark_image.attach(io: StringIO.new("watermark"), filename: "watermark.png", content_type: "image/png")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("foto enviada direto"),
      filename: "direct-watermark.jpg",
      content_type: "image/jpeg"
    )

    expect do
      patch admin_habitation_path(habitation), params: {
        habitation: {
          titulo_anuncio: "Título com direct upload",
          apply_photo_watermark: "1",
          photos: [blob.signed_id]
        }
      }
    end.to have_enqueued_job(HabitationPhotoWatermarkJob)

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload.photos.attachments.size).to eq(1)
  end

  it "mantém fotos da API ao adicionar fotos anexadas" do
    api_pictures = [
      { "url" => "https://example.com/api-um.jpg" },
      { "url" => "https://example.com/api-dois.jpg" }
    ]
    habitation = create(
      :habitation,
      codigo: "FOTO-API-KEEP-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Título antigo",
      pictures: api_pictures
    )
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "105",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    uploaded_photo = Tempfile.new(["foto-local", ".jpg"])
    uploaded_photo.write("foto local")
    uploaded_photo.rewind

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: "Título com API preservada",
        photos: [Rack::Test::UploadedFile.new(uploaded_photo.path, "image/jpeg")]
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    habitation.reload
    expect(habitation.pictures).to eq(api_pictures)
    expect(habitation.photos.attachments.size).to eq(1)
  ensure
    uploaded_photo&.close
    uploaded_photo&.unlink
  end

  it "exibe fotos da API junto com fotos anexadas na edição" do
    habitation = create(
      :habitation,
      codigo: "FOTO-MIX-#{SecureRandom.hex(6)}",
      pictures: [{ "url" => "https://example.com/api-visivel.jpg" }]
    )
    habitation.photos.attach(
      io: StringIO.new("foto local"),
      filename: "local.jpg",
      content_type: "image/jpeg"
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("local.jpg")
    expect(response.body).to include("https://example.com/api-visivel.jpg")
  end

  it "remove fotos anexadas selecionadas ao salvar o imóvel" do
    habitation = create(:habitation, codigo: "FOTO-DEL-#{SecureRandom.hex(6)}")
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "102",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    habitation.photos.attach(
      io: StringIO.new("foto um"),
      filename: "foto-um.jpg",
      content_type: "image/jpeg"
    )
    habitation.photos.attach(
      io: StringIO.new("foto dois"),
      filename: "foto-dois.jpg",
      content_type: "image/jpeg"
    )
    attachments = habitation.photos.attachments.order(:id).to_a
    habitation.update!(photo_ids_order: attachments.map(&:id))

    perform_enqueued_jobs do
      patch admin_habitation_path(habitation), params: {
        habitation: {
          titulo_anuncio: "Título mantendo uma foto",
          ordered_photo_ids: attachments.map(&:id).join(","),
          remove_photo_ids: attachments.first.id.to_s
        }
      }
    end

    expect(response).to redirect_to(admin_habitations_path)
    habitation.reload
    expect(habitation.photos.attachments.map(&:id)).to contain_exactly(attachments.second.id)
    expect(habitation.photo_ids_order).to eq([attachments.second.id])
    expect(HabitationAuditLog.where(habitation_id: habitation.id, action: "attachments_changed").last.changed_fields).to include("photos_attachments")
  end

  it "remove fotos da API selecionadas ao salvar o imóvel" do
    habitation = create(
      :habitation,
      codigo: "FOTO-API-#{SecureRandom.hex(6)}",
      pictures: [
        { "url" => "https://example.com/um.jpg" },
        { "url" => "https://example.com/dois.jpg" },
        { "url" => "https://example.com/tres.jpg" }
      ]
    )
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "103",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: "Título sem a segunda foto API",
        remove_picture_indices: "1"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload.pictures.map { |picture| picture["url"] }).to eq([
      "https://example.com/um.jpg",
      "https://example.com/tres.jpg"
    ])
  end

  it "salva fotos internas sem removê-las do cadastro" do
    habitation = create(
      :habitation,
      codigo: "FOTO-INTERNA-#{SecureRandom.hex(6)}",
      pictures: [
        { "url" => "https://example.com/api-site.jpg" },
        { "url" => "https://example.com/api-interna.jpg" }
      ]
    )
    habitation.create_address!(
      logradouro: "Rua Fotos",
      numero: "106",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    habitation.photos.attach(
      io: StringIO.new("foto site"),
      filename: "foto-site.jpg",
      content_type: "image/jpeg"
    )
    habitation.photos.attach(
      io: StringIO.new("foto interna"),
      filename: "foto-interna.jpg",
      content_type: "image/jpeg"
    )
    attachments = habitation.photos.attachments.order(:id).to_a

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: "Título com fotos internas",
        site_hidden_photo_ids: attachments.second.id.to_s,
        site_hidden_picture_urls: "https://example.com/api-interna.jpg"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    habitation.reload
    expect(habitation.photos.attachments.map(&:id)).to contain_exactly(*attachments.map(&:id))
    expect(habitation.site_hidden_photo_ids).to contain_exactly(attachments.second.id)
    expect(habitation.pictures.second["site_hidden"]).to eq(true)
    expect(habitation.public_image_sources.map { |source| source["url"] }).not_to include("https://example.com/api-interna.jpg")
    expect(habitation.public_image_sources.filter_map { |source| source["attachment"] }).not_to include(attachments.second)
  end

  it "exibe modal para escolher como concluir o salvamento do cadastro" do
    habitation = create(:habitation, codigo: "SAVE-MODAL-#{SecureRandom.hex(6)}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Como deseja salvar?")
    expect(response.body).to include("Salvar e permanecer")
    expect(response.body).to include("Salvar e sair")
    expect(response.body).to include("Cancelar")
    expect(response.body).to include("data-habitation-save-options-form")
    expect(response.body).to include("data-habitation-save-options-action")
  end

  it "permanece na ficha de cadastro quando solicitado no salvamento" do
    habitation = create(:habitation, codigo: "SAVE-STAY-#{SecureRandom.hex(6)}", titulo_anuncio: "Título antigo")
    habitation.create_address!(
      logradouro: "Rua Salvamento",
      numero: "123",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    patch admin_habitation_path(habitation), params: {
      save_navigation: "stay",
      habitation: {
        titulo_anuncio: "Título salvo na ficha"
      }
    }

    expect(response).to redirect_to(edit_admin_habitation_path(habitation))
    follow_redirect!
    expect(response.body).to include("Imóvel atualizado com sucesso. Você permaneceu na ficha de cadastro.")
    expect(habitation.reload.titulo_anuncio).to eq("Título salvo na ficha")
  end

  it "atualiza o seletor Exibir no site no cadastro do imóvel" do
    habitation = create(:habitation, codigo: "SITE-FLAG-#{SecureRandom.hex(6)}", exibir_no_site_flag: false)
    habitation.create_address!(
      logradouro: "Rua Site Flag",
      numero: "10",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: habitation.titulo_anuncio,
        exibir_no_site_flag: "1"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload.exibir_no_site_flag).to be(true)

    patch admin_habitation_path(habitation), params: {
      habitation: {
        titulo_anuncio: habitation.titulo_anuncio,
        exibir_no_site_flag: "0"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload.exibir_no_site_flag).to be(false)
  end

  it "oculta classificação de fotos da ficha de pré-cadastro do corretor" do
    broker_profile = Profile.create!(
      name: "Corretor #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile)
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: broker,
      codigo: "FOTO-COR-#{SecureRandom.hex(6)}",
      intake_status: "returned_to_broker"
    )

    sign_in broker
    get edit_admin_habitation_path(intake)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Classificação das Fotos:")
  end

  it "exibe anexos internos para perfil administrativo revisar autorização" do
    administrative_profile = Profile.create!(
      name: "Administrativo",
      active: true,
      permissions: Profile.default_permissions_for("Administrativo")
    )
    administrative_user = create(:admin_user, profile: administrative_profile)
    intake = create(:habitation, :broker_intake, admin_user: admin, codigo: "DOC-ADM-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review")
    intake.autorizacoes_venda.attach(
      io: StringIO.new("autorizacao"),
      filename: "autorizacao-administrativo.txt",
      content_type: "text/plain"
    )

    sign_in administrative_user
    get edit_admin_habitation_path(intake)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    documents_pane = page.at_css("#habitationTabsContent > #documents")

    expect(documents_pane).to be_present
    expect(documents_pane["role"]).to eq("tabpanel")
    expect(documents_pane["aria-labelledby"]).to eq("documents-tab")
    expect(response.body).to include("Autorizações de Venda")
    expect(response.body).to include("autorizacao-administrativo.txt")
    expect(response.body).to include("Adicionar arquivos")
  end

  it "anexa fichas de cadastro e autorizações pela aba de documentos" do
    habitation = create(:habitation, codigo: "DOC-UP-#{SecureRandom.hex(6)}")
    habitation.create_address!(
      logradouro: "Rua Upload Documento",
      numero: "10",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    ficha = Rack::Test::UploadedFile.new(
      StringIO.new("ficha de cadastro"),
      "text/plain",
      original_filename: "ficha-cadastro.txt"
    )
    autorizacao = Rack::Test::UploadedFile.new(
      StringIO.new("autorizacao de venda"),
      "text/plain",
      original_filename: "autorizacao-venda.txt"
    )

    patch admin_habitation_path(habitation), params: {
      save_navigation: "stay",
      save_anchor: "documents",
      document_upload: "fichas_cadastro",
      habitation: {
        fichas_cadastro: [ficha]
      }
    }

    expect(response).to redirect_to(edit_admin_habitation_path(habitation, anchor: "documents"))
    expect(habitation.reload.fichas_cadastro.attachments.map { |attachment| attachment.filename.to_s }).to include("ficha-cadastro.txt")

    patch admin_habitation_path(habitation), params: {
      save_navigation: "stay",
      save_anchor: "documents",
      document_upload: "autorizacoes_venda",
      habitation: {
        autorizacoes_venda: [autorizacao]
      }
    }

    expect(response).to redirect_to(edit_admin_habitation_path(habitation, anchor: "documents"))
    expect(habitation.reload.autorizacoes_venda.attachments.map { |attachment| attachment.filename.to_s }).to include("autorizacao-venda.txt")
  end

  it "abre cadastro de proprietário em modal no formulário do imóvel" do
    habitation = create(:habitation, codigo: "PROP-MODAL-#{SecureRandom.hex(6)}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="quickProprietorModal"')
    expect(response.body).to include(quick_create_admin_proprietors_path)
    expect(response.body).to include("Salvar e selecionar")
    expect(response.body).not_to include("<iframe")
    expect(response.body).not_to include(new_admin_proprietor_path(embed: "modal"))
  end

  it "permite captador visualizar documentos sem anexar ou remover" do
    broker_profile = Profile.create!(
      name: "Corretor docs #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile)
    habitation = create(:habitation, :broker_intake, admin_user: broker, codigo: "DOC-COR-#{SecureRandom.hex(6)}", intake_status: "returned_to_broker")
    habitation.fichas_cadastro.attach(
      io: StringIO.new("ficha"),
      filename: "ficha.txt",
      content_type: "text/plain"
    )
    attachment = habitation.fichas_cadastro.attachments.first

    sign_in broker
    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ficha.txt")
    expect(response.body).not_to include("Adicionar arquivos")
    expect(response.body).not_to include(purge_attachment_admin_habitation_path(habitation, association: "fichas_cadastro", attachment_id: attachment.id))

    delete purge_attachment_admin_habitation_path(habitation, association: "fichas_cadastro", attachment_id: attachment.id)

    expect(response).to redirect_to(edit_admin_habitation_path(habitation, anchor: "documents"))
    expect(habitation.reload.fichas_cadastro.attachments.count).to eq(1)
  end

  it "mostra resumo e fotos no detalhe sem expor cadastro interno para corretor não captador" do
    broker_profile = Profile.create!(
      name: "Corretor show restrito #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    captador = create(:admin_user, profile: broker_profile, name: "Captador Responsável")
    other_broker = create(:admin_user, profile: broker_profile, name: "Outro Corretor")
    habitation = create(
      :habitation,
      admin_user: captador,
      codigo: "SHOW-REST-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento completo para show",
      proprietario: "Proprietário Sigiloso",
      proprietario_celular: "(47) 99999-9999",
      nome_empreendimento: "Edifício Visível",
      area_privativa_m2: 123,
      tour_virtual: "https://example.com/tour",
      videos: ["https://example.com/video"],
      permuta_localizacao: "Balneário Camboriú",
      tipo_veiculo_aceito_permuta: "SUV",
      intake_origin: Habitation::INTAKE_ORIGIN_BROKER,
      intake_status: "internal",
      vista_referencia_externa: "VISTA-REF-1",
      praia_brava_flag: true,
      home_corporate_flag: true,
      pictures: [{ "url" => "https://example.com/foto-api-show.jpg" }]
    )
    habitation.create_address!(
      logradouro: "Rua Show",
      numero: "77",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    habitation.photos.attach(
      io: StringIO.new("foto local show"),
      filename: "foto-local-show.jpg",
      content_type: "image/jpeg"
    )
    habitation.fichas_cadastro.attach(
      io: StringIO.new("documento sigiloso"),
      filename: "ficha-sigilosa.txt",
      content_type: "text/plain"
    )
    habitation.broker_assignments.create!(
      admin_user: captador,
      role: "captador",
      commission_type: "percentage",
      commission_value: 4.5,
      observations: "Vínculo de captação"
    )

    sign_in other_broker
    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Apartamento completo para show")
    expect(response.body).to include("Edifício Visível")
    expect(response.body).to include("https://example.com/foto-api-show.jpg")
    expect(response.body).to include("foto-local-show.jpg")
    expect(response.body).to include("data-fancybox")
    expect(response.body).to include("Informações principais")
    expect(response.body).to include("Captador")
    expect(response.body).to include("Captador Responsável")
    expect(response.body).to include("Valores")
    expect(response.body).to include("Endereço")
    expect(response.body).to include("Características")
    expect(response.body).to include("Mídia complementar")
    expect(response.body).to include("Balneário Camboriú")
    expect(response.body).to include("https://example.com/tour")
    expect(response.body).to include("https://example.com/video")
    expect(response.body).not_to include("Responsáveis e vínculos")
    expect(response.body).not_to include("Captação e revisão")
    expect(response.body).not_to include("Integrações e códigos externos")
    expect(response.body).not_to include("Publicação, portais e SEO")
    expect(response.body).not_to include("VISTA-REF-1")
    expect(response.body).not_to include("SUV")
    expect(response.body).not_to include("Vínculo de captação")
    expect(response.body).not_to include("Proprietário Sigiloso")
    expect(response.body).not_to include("(47) 99999-9999")
    expect(response.body).not_to include("ficha-sigilosa.txt")
    expect(response.body).not_to include("Anexos e documentos internos")
  end

  it "mantém proprietário e anexos fora do detalhe simplificado para o captador do imóvel" do
    broker_profile = Profile.create!(
      name: "Corretor show captador #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    captador = create(:admin_user, profile: broker_profile, name: "Captador Show")
    habitation = create(
      :habitation,
      admin_user: captador,
      codigo: "SHOW-CAP-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel do captador",
      proprietario: "Proprietário do Captador",
      proprietario_email: "proprietario@example.com"
    )
    habitation.fichas_cadastro.attach(
      io: StringIO.new("documento"),
      filename: "ficha-captador.txt",
      content_type: "text/plain"
    )

    sign_in captador
    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Imóvel do captador")
    expect(response.body).to include("Editar cadastro")
    expect(response.body).not_to include("Proprietário do Captador")
    expect(response.body).not_to include("proprietario@example.com")
    expect(response.body).not_to include("Anexos e documentos internos")
    expect(response.body).not_to include("ficha-captador.txt")
  end

  it "bloqueia campos sensíveis para corretor ao editar imóvel atribuído" do
    broker_profile = Profile.create!(
      name: "Corretor edição limitada #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile)
    habitation = create(
      :habitation,
      admin_user: broker,
      codigo: "LOCK-#{SecureRandom.hex(6)}",
      nome_empreendimento: "Empreendimento Original",
      titulo_anuncio: "Título Original",
      descricao_web: "Descrição Original",
      proprietario: "Proprietário Original",
      proprietario_email: "original@example.com",
      valor_venda_cents: 500_000_00
    )
    habitation.create_address!(
      logradouro: "Rua Original",
      numero: "10",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    file = Tempfile.new(["ficha-bloqueada", ".txt"])
    file.write("ficha bloqueada")
    file.rewind

    sign_in broker
    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('input[name="habitation[titulo_anuncio]"]')["readonly"]).to eq("readonly")
    expect(page.at_css('input[name="habitation[nome_empreendimento]"]')["readonly"]).to eq("readonly")
    expect(page.at_css('input[name="habitation[proprietario]"]')["readonly"]).to eq("readonly")
    expect(page.at_css('input[name="habitation[address_attributes][logradouro]"]')["readonly"]).to eq("readonly")
    expect(response.body).not_to include("Adicionar arquivos")

    patch admin_habitation_path(habitation), params: {
      habitation: {
        status: "Aluguel",
        categoria: "Apartamento",
        dormitorios_qtd: "3",
        caracteristicas: ["Mobiliado", "Vista mar"],
        valor_venda_formatted: "600.000,00",
        nome_empreendimento: "Empreendimento Alterado",
        titulo_anuncio: "Título Alterado",
        descricao_web: "Descrição Alterada",
        proprietario: "Proprietário Alterado",
        proprietario_email: "alterado@example.com",
        fichas_cadastro: [Rack::Test::UploadedFile.new(file.path, "text/plain")],
        address_attributes: {
          id: habitation.address.id,
          logradouro: "Rua Alterada",
          numero: "99",
          bairro: "Outro Bairro",
          cidade: "Itajaí",
          uf: "SC"
        }
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    habitation.reload
    expect(habitation).to have_attributes(
      status: "Aluguel",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 600_000_00,
      nome_empreendimento: "Empreendimento Original",
      titulo_anuncio: "Título Original",
      proprietario: "Proprietário Original",
      proprietario_email: "original@example.com"
    )
    expect(habitation.caracteristicas).to include("Mobiliado", "Vista mar")
    expect(habitation.display_description).to include("Descrição Original")
    expect(habitation.display_description).not_to include("Descrição Alterada")
    expect(habitation.address.reload).to have_attributes(
      logradouro: "Rua Original",
      numero: "10",
      bairro: "Centro",
      cidade: "Balneário Camboriú"
    )
    expect(habitation.fichas_cadastro).not_to be_attached
  ensure
    file&.close
    file&.unlink
  end

  it "registra auditoria de alteração do imóvel e exibe o botão de timeline" do
    habitation = create(:habitation, codigo: "AUD-#{SecureRandom.hex(6)}", titulo_anuncio: "Título antigo", exibir_no_site_flag: false)
    habitation.create_address!(
      logradouro: "Rua Auditoria",
      numero: "10",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    expect {
      patch admin_habitation_path(habitation), params: {
        habitation: {
          titulo_anuncio: "Título novo",
          valor_venda_formatted: "950.000,00",
          exibir_no_site_flag: "1"
        }
      }
    }.to change(HabitationAuditLog, :count).by(1)

    expect(response).to redirect_to(admin_habitations_path)
    log = HabitationAuditLog.last
    expect(log).to have_attributes(habitation_id: habitation.id, admin_user_id: admin.id, action: "published")
    expect(log.changed_fields).to include("titulo_anuncio", "valor_venda_cents", "exibir_no_site_flag")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Timeline")
    expect(response.body).to include("Título do anúncio")
    expect(response.body).to include("Título antigo")
    expect(response.body).to include("Título novo")
  end

  it "exibe eventos importados do Vista na timeline do cadastro" do
    habitation = create(:habitation, codigo: "VISTA-TL-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel com timeline Vista")
    HabitationInteraction.create!(
      habitation: habitation,
      admin_user: admin,
      source_table: "VISTA_API_PRONTUARIO",
      source_key: "#{habitation.codigo}:123",
      vista_habitation_code: habitation.codigo,
      subject: "Atualização importada do Vista",
      body: "Descrição alterada no prontuário",
      status: "Concluído",
      occurred_at: Time.zone.parse("2026-06-01 10:30")
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Vista")
    expect(response.body).to include("Atualização importada do Vista")
    expect(response.body).to include("Descrição alterada no prontuário")
    expect(response.body).to include("VISTA_API_PRONTUARIO")
  end

  it "exibe documentos importados do Vista na aba de documentos" do
    habitation = create(:habitation, codigo: "VISTA-DOC-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel com documento Vista")
    batch = VistaImportBatch.create!(dump_dir: "spec/vista", status: "completed")
    VistaFileAsset.create!(
      vista_import_batch: batch,
      habitation: habitation,
      table_name: "API_DOCUMENTOS",
      kind: "property_document",
      status: "pending",
      codigo_imovel: habitation.codigo,
      source_path: "documentos/#{habitation.codigo}/autorizacao.pdf",
      source_url: "https://arquivos.example.test/autorizacao.pdf",
      filename: "autorizacao-vista.pdf",
      active_storage_name: "autorizacoes_venda"
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Documentos do Vista")
    expect(response.body).to include("autorizacao-vista.pdf")
    expect(response.body).to include("Pendente de download")
    expect(response.body).to include("https://arquivos.example.test/autorizacao.pdf")
  end

  it "não exibe bloco de documentos do Vista para imóvel de ficha interna sem integração" do
    habitation = create(
      :habitation,
      :broker_intake,
      codigo: "FICHA-SEM-VISTA-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Ficha concluída internamente",
      intake_status: "internal",
      vista_import_batch_id: nil,
      vista_codigo: nil,
      vista_imo_codigo: nil,
      vista_referencia_externa: nil,
      status_vista: nil
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Documentos do Vista")
    expect(response.body).not_to include("Nenhum documento do Vista vinculado a este imóvel")
  end

  it "registra qualquer campo do cadastro do imóvel, mesmo fora da lista principal" do
    habitation = create(:habitation, codigo: "AUD-FULL-#{SecureRandom.hex(6)}", festival_salute_flag: false, ocupacao_status: "Desocupado")
    habitation.create_address!(
      logradouro: "Rua Auditoria",
      numero: "20",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    patch admin_habitation_path(habitation), params: {
      habitation: {
        festival_salute_flag: "1",
        ocupacao_status: "Ocupado",
        address_attributes: {
          id: habitation.address.id,
          logradouro: "Rua Auditoria Atualizada",
          numero: "20",
          bairro: "Centro",
          cidade: "Balneário Camboriú",
          uf: "SC"
        }
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    log = HabitationAuditLog.where(habitation_id: habitation.id).last
    expect(log.changed_fields).to include("festival_salute_flag", "ocupacao_status", "address.logradouro")

    get edit_admin_habitation_path(habitation)

    expect(response.body).to include("Festival salute flag")
    expect(response.body).to include("Ocupacao status")
    expect(response.body).to include("Rua Auditoria Atualizada")
  end

  it "registra uploads e remoções de fotos e documentos no histórico" do
    habitation = create(:habitation, codigo: "AUD-DOC-#{SecureRandom.hex(6)}")
    habitation.create_address!(
      logradouro: "Rua Documentos",
      numero: "30",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    file = Tempfile.new(["autorizacao", ".txt"])
    file.write("autorizacao")
    file.rewind

    expect {
      patch admin_habitation_path(habitation), params: {
        habitation: {
          autorizacoes_venda: [
            Rack::Test::UploadedFile.new(file.path, "text/plain")
          ]
        }
      }
    }.to change(HabitationAuditLog, :count).by(1)

    expect(response).to redirect_to(admin_habitations_path)
    upload_log = HabitationAuditLog.last
    expect(upload_log).to have_attributes(action: "attachments_changed")
    expect(upload_log.changed_fields).to include("autorizacoes_venda_attachments")

    attachment = habitation.reload.autorizacoes_venda.attachments.first
    return_path = admin_habitations_path(ownership: "all", q: habitation.codigo)
    expect {
      delete "/admin/habitations/#{habitation.id}/purge_attachment/autorizacoes_venda/#{attachment.id}", params: { return_to: return_path }
    }.to change(HabitationAuditLog, :count).by(1)

    expect(response).to redirect_to(edit_admin_habitation_path(habitation, return_to: return_path, anchor: "documents"))
    remove_log = HabitationAuditLog.last
    expect(remove_log).to have_attributes(action: "attachments_changed")
    expect(remove_log.changed_fields).to include("autorizacoes_venda_attachments")
    expect(remove_log.change_summaries.first[:before]).to include("autorizacao")
  ensure
    file&.close
    file&.unlink
  end

  it "registra vínculo de corretores e publicação em massa no histórico" do
    broker = create(:admin_user, name: "Corretor Auditor")
    habitation = create(:habitation, codigo: "AUD-BULK-#{SecureRandom.hex(6)}", exibir_no_site_flag: false)
    habitation.create_address!(
      logradouro: "Rua Massa",
      numero: "40",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    patch admin_habitation_path(habitation), params: {
      habitation: {
        broker_assignments_attributes: {
          "0" => {
            admin_user_id: broker.id,
            role: "captador",
            commission_type: "percentage",
            commission_value: "2.5"
          }
        }
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    broker_log = HabitationAuditLog.where(habitation_id: habitation.id).last
    expect(broker_log).to have_attributes(action: "broker_assignments_changed")
    expect(broker_log.changed_fields).to include("broker_assignments")
    expect(broker_log.change_summaries.first[:after]).to include("Corretor Auditor")

    expect {
      post bulk_publish_admin_habitations_path, params: {
        selected_ids: [habitation.id],
        action_type: "publicar",
        channels: %w[site]
      }
    }.to change(HabitationAuditLog, :count).by(1)

    bulk_log = HabitationAuditLog.last
    expect(bulk_log).to have_attributes(action: "bulk_updated", habitation_id: habitation.id)
    expect(bulk_log.changed_fields).to include("exibir_no_site_flag")
  end

  it "bloqueia cadastro de imóvel com mesma rua, número, prédio e unidade" do
    existing = create(:habitation, codigo: "DUP-#{SecureRandom.hex(6)}", nome_empreendimento: "Edifício Aurora", bloco: "1203")
    existing.create_address!(
      logradouro: "Rua 1500",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    expect {
      post admin_habitations_path, params: {
        habitation: {
          categoria: "Apartamento",
          status: "Venda",
          tipo: "Unitário",
          nome_empreendimento: "Edificio Aurora",
          bloco: "Apto 1203",
          address_attributes: {
            logradouro: "Rua 1500",
            numero: "100",
            bairro: "Centro",
            cidade: "Balneário Camboriú",
            uf: "SC"
          }
        }
      }
    }.not_to change(Habitation, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Já existe imóvel cadastrado")
  end

  it "permite casa em condomínio no mesmo endereço com complemento diferente" do
    existing = create(:habitation, codigo: "COND-#{SecureRandom.hex(6)}", categoria: "Casa em Condomínio", bloco: "")
    existing.create_address!(
      logradouro: "Rua Higino João Pio",
      numero: "420",
      complemento: "01",
      bairro: "Praia do Estaleirinho",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    expect {
      post admin_habitations_path, params: {
        habitation: {
          categoria: "Casa em Condomínio",
          status: "Venda",
          tipo: "Unitário",
          bloco: "",
          address_attributes: {
            logradouro: "Rua Higino João Pio",
            numero: "420",
            complemento: "02",
            bairro: "Praia do Estaleirinho",
            cidade: "Balneário Camboriú",
            uf: "SC"
          }
        }
      }
    }.to change(Habitation, :count).by(1)

    expect(response).to redirect_to(admin_habitations_path)
  end

  it "retorna duplicidade em tempo real por endereço completo" do
    existing = create(:habitation, codigo: "CHK-#{SecureRandom.hex(6)}", nome_empreendimento: "Edifício Aurora", bloco: "1203")
    existing.create_address!(
      logradouro: "Rua 1500",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    get check_admin_habitation_duplicate_path, params: {
      street: "rua 1500",
      number: "100",
      building: "Edificio Aurora",
      unit: "apto 1203",
      status: "Venda"
    }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload.fetch("complete")).to eq(true)
    expect(payload.fetch("duplicate")).to eq(true)
    expect(payload.fetch("matches").first.fetch("codigo")).to eq(existing.codigo)
  end

  it "não retorna duplicidade em tempo real quando status comercial é diferente" do
    existing = create(:habitation, codigo: "CHK-STATUS-#{SecureRandom.hex(6)}", status: "Venda", nome_empreendimento: "Edifício Aurora", bloco: "1203")
    existing.create_address!(
      logradouro: "Rua 1500",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    get check_admin_habitation_duplicate_path, params: {
      street: "rua 1500",
      number: "100",
      building: "Edificio Aurora",
      unit: "apto 1203",
      status: "Aluguel"
    }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload.fetch("complete")).to eq(true)
    expect(payload.fetch("duplicate")).to eq(false)
    expect(payload.fetch("matches")).to be_empty
  end
end
