require "rails_helper"
require "tempfile"

RSpec.describe "Admin::Habitations", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin, email: "admin-#{SecureRandom.hex(8)}@salute.test") }
  let(:turbo_frame_headers) { { "Turbo-Frame" => "admin_habitations_filter_inspector" } }

  def default_agent_profile
    Tenant.default.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
  end

  def default_administrative_profiles
    internal_management_profile = Tenant.default.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME).tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Administrativo"))
    end
    administrative_profile = Tenant.default.profiles.find_by!(key: "administrativo").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Administrativo"))
    end

    [internal_management_profile, administrative_profile]
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe de/para no resumo do imóvel quando o preço de venda foi reduzido" do
    habitation = create(
      :habitation,
      codigo: "DISC-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento com valor reduzido",
      valor_venda_cents: 3_950_000_00,
      valor_venda_anterior_cents: 4_200_000_00
    )

    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Apartamento com valor reduzido")
    expect(response.body).to include("De")
    expect(response.body).to include("R$ 4.200.000,00")
    expect(response.body).to include("R$ 3.950.000,00")
    expect(response.body).to include("abaixo do valor anterior")
  end

  it "exibe de/para no resumo do imóvel quando o preço de locação foi reduzido" do
    habitation = create(
      :habitation,
      codigo: "RENT-DISC-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento com aluguel reduzido",
      status: "Aluguel",
      valor_venda_cents: 0,
      valor_locacao_cents: 8_000_00,
      valor_locacao_anterior_cents: 10_000_00
    )

    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Apartamento com aluguel reduzido")
    expect(response.body).to include("R$ 10.000,00")
    expect(response.body).to include("R$ 8.000,00/mês")
    expect(response.body).to include("Locação com preço reduzido")
  end

  it "exibe o box da vaga na estrutura do detalhe do imóvel" do
    habitation = create(
      :habitation,
      codigo: "BOX-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento com box identificado",
      tipo_vaga: "Privativa",
      numero_box: "G-12"
    )

    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tipo de vaga")
    expect(response.body).to include("Privativa")
    expect(response.body).to include(">Box<")
    expect(response.body).to include("G-12")
    expect(response.body).not_to include("Box garagem")
  end

  it "exibe administração de locação no painel de valores" do
    habitation = create(
      :habitation,
      codigo: "ADM-LOC-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento com administração de locação",
      salute_rental_management_flag: true
    )

    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Com Adm")
    expect(response.body).to include("Sim")
  end

  it "exibe parcelamento e quantidade de parcelas no painel de valores" do
    habitation = create(
      :habitation,
      codigo: "PARC-SHOW-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento com parcelamento",
      aceita_financiamento_flag: true,
      aceita_parcelamento_flag: true,
      numero_prestacoes: 24
    )

    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aceita parcelamento")
    expect(response.body).to include("24x")
    expect(response.body).not_to include("Aceita financiamento")
  end

  it "exibe campos de parcelamento no cadastro administrativo" do
    habitation = create(:habitation, codigo: "PARC-FORM-#{SecureRandom.hex(6)}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aceita parcelamento")
    expect(response.body).to include("Qtd. parcelas")
    expect(response.body).to include("habitation_aceita_parcelamento_flag")
    expect(response.body).to include("habitation_numero_prestacoes")
  end

  it "renderiza os contextos reativos ativos organizados em painéis" do
    habitation = create(
      :habitation,
      codigo: "REACTIVE-FORM-#{SecureRandom.hex(6)}",
      aceita_parcelamento_flag: true,
      numero_prestacoes: 24,
      home_corporate_flag: true,
      home_corporate_position: 3,
      status: "Vendido terceiros",
      valor_vendido_terceiros_cents: 850_000_00,
      key_location: "Portaria",
      vagas_qtd: 2,
      tipo_vaga: "Privativa",
      numero_box: "G-12"
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    active_fields = %w[
      habitation_numero_prestacoes
      habitation_home_corporate_position
      habitation_valor_vendido_terceiros_formatted
      habitation_senha_portaria
      habitation_tipo_vaga
      habitation_numero_box
    ]

    active_fields.each do |field_id|
      field = html.at_css("##{field_id}")
      panel = field&.ancestors&.find { |ancestor| ancestor["data-conditional-reveal-target"] == "panel" || ancestor["data-habitation-form-target"].to_s.end_with?("StatusPanel") }

      expect(field).to be_present
      expect(field.key?("disabled")).to be(false)
      expect(panel).to be_present
      expect(panel.key?("hidden")).to be(false)
    end

    expect(html.at_css('[data-habitation-form-target="rentedStatusPanel"]').key?("hidden")).to be(true)
  end

  it "preserva contextos legados ambíguos sem ativar o seletor automaticamente" do
    habitation = create(
      :habitation,
      codigo: "REACTIVE-LEGACY-#{SecureRandom.hex(6)}",
      key_location: nil,
      key_location_notes: "Retirar com pessoa indicada pelo proprietário",
      vagas_qtd: 0,
      tipo_vaga: "Privativa",
      numero_box: "B-07",
      publicar_imovelweb_2: false,
      tipo_publicacao_imovelweb_2: "Destaque"
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    key_panel = html.at_css('#habitation_key_location_notes').ancestors.find { |ancestor| ancestor["data-conditional-reveal-target"] == "panel" }
    parking_panel = html.at_css('#habitation_numero_box').ancestors.find { |ancestor| ancestor["data-conditional-reveal-target"] == "panel" }
    portal_group = html.at_css('#habitation_publicar_imovelweb_2').ancestors.find { |ancestor| ancestor["data-controller"].to_s.split.include?("conditional-reveal") }
    portal_panel = portal_group.at_css('[data-conditional-reveal-target="panel"]')

    expect(key_panel["data-conditional-reveal-preserve"]).to eq("true")
    expect(key_panel.key?("hidden")).to be(false)
    expect(parking_panel["data-conditional-reveal-preserve"]).to eq("true")
    expect(parking_panel.key?("hidden")).to be(false)
    expect(portal_panel.key?("hidden")).to be(true)
    expect(habitation.reload.publicar_imovelweb_2).to be(false)
  end

  it "renderiza contextos cumulativos para os itens aceitos na permuta" do
    habitation = create(
      :habitation,
      codigo: "PERMUTA-FORM-#{SecureRandom.hex(6)}",
      aceita_permuta_flag: true,
      aceita_permuta_veiculo_flag: true,
      aceita_permuta_imovel_flag: true,
      aceita_permuta_outros_flag: true,
      permuta_veiculo_valor_cents: 80_000_00,
      permuta_valor_cents: 500_000_00,
      permuta_outros_valor_cents: 20_000_00
    )

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    exchange = html.at_css('[data-controller~="habitation-exchange"]')

    expect(exchange).to be_present
    expect(exchange.at_css('[data-habitation-exchange-target="vehiclePanel"]').key?("hidden")).to be(false)
    expect(exchange.at_css('[data-habitation-exchange-target="propertyPanel"]').key?("hidden")).to be(false)
    expect(exchange.at_css('[data-habitation-exchange-target="othersPanel"]').key?("hidden")).to be(false)
    expect(exchange.css('[data-exchange-required="true"][required]').size).to eq(3)
    expect(response.body).to include("Valor do veículo", "Valor do imóvel", "Valor dos outros itens")
  end

  it "persiste os valores e o contexto de cada item da permuta" do
    habitation = create(:habitation, codigo: "PERMUTA-SAVE-#{SecureRandom.hex(6)}")

    patch admin_habitation_path(habitation), params: {
      habitation: {
        aceita_permuta_flag: "1",
        aceita_permuta_veiculo_flag: "1",
        aceita_permuta_imovel_flag: "1",
        aceita_permuta_outros_flag: "1",
        valor_aceito_permuta_formatted: "R$ 715.000,00",
        permuta_veiculo_valor_formatted: "R$ 95.000,00",
        tipo_veiculo_aceito_permuta: "SUV",
        ano_minimo_veiculo_aceito_permuta: "2022",
        permuta_valor_formatted: "R$ 600.000,00",
        permuta_localizacao: "Balneário Camboriú",
        permuta_dormitorios_qtd: "3",
        permuta_suites_qtd: "1",
        permuta_garagens_qtd: "2",
        permuta_outros_valor_formatted: "R$ 20.000,00",
        permuta_outros_descricao: "Embarcação"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload).to have_attributes(
      aceita_permuta_flag: true,
      aceita_permuta_veiculo_flag: true,
      aceita_permuta_imovel_flag: true,
      aceita_permuta_outros_flag: true,
      valor_aceito_permuta_cents: 71_500_000,
      permuta_veiculo_valor_cents: 9_500_000,
      permuta_valor_cents: 60_000_000,
      permuta_outros_valor_cents: 2_000_000,
      permuta_outros_descricao: "Embarcação"
    )
  end

  it "não exibe detalhes de tipos de permuta que não estão selecionados" do
    habitation = create(
      :habitation,
      codigo: "PERMUTA-SHOW-#{SecureRandom.hex(6)}",
      aceita_permuta_flag: true,
      aceita_permuta_veiculo_flag: true,
      aceita_permuta_imovel_flag: false,
      permuta_veiculo_valor_cents: 90_000_00,
      tipo_veiculo_aceito_permuta: "SUV",
      permuta_localizacao: "Dado antigo oculto"
    )

    get admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Valor do veículo", "SUV")
    expect(response.body).not_to include("Dado antigo oculto")
  end

  it "salva as opções públicas de mapa e vista da rua do imóvel" do
    habitation = create(:habitation, codigo: "PUBLIC-MAP-#{SecureRandom.hex(6)}")

    patch admin_habitation_path(habitation), params: {
      habitation: {
        public_map_display_mode: "exact",
        public_street_view_mode: "enabled"
      }
    }

    expect(response).to redirect_to(admin_habitations_path)
    expect(habitation.reload).to have_attributes(
      public_map_display_mode: "exact",
      public_street_view_mode: "enabled"
    )
  end

  it "posiciona a publicação em portais abaixo dos responsáveis na aba comercial" do
    habitation = create(:habitation, codigo: "PORTAL-FORM-#{SecureRandom.hex(6)}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    side_column = html.at_css("#comercial .ax-commercial-column--side")
    responsible_section = side_column.at_xpath("./section[.//span[normalize-space()='Responsáveis e agenciamento']]")
    portal_section = side_column.at_xpath(
      "./div[contains(concat(' ', normalize-space(@class), ' '), ' portal-publication-section ')]"
    )

    expect(responsible_section).to be_present
    expect(portal_section).to be_present
    expect(side_column.element_children.index(portal_section)).to eq(
      side_column.element_children.index(responsible_section) + 1
    )
  end

  it "separa captações restritas da listagem geral de imóveis" do
    draft = create(:habitation, :broker_intake, admin_user: admin, codigo: "DRAFT-#{SecureRandom.hex(6)}", titulo_anuncio: "Captação em rascunho")
    submitted = create(:habitation, :broker_intake, admin_user: admin, codigo: "REV-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review", titulo_anuncio: "Captação finalizada")
    approved = create(:habitation, :broker_intake, admin_user: admin, codigo: "APP-#{SecureRandom.hex(6)}", intake_status: "admin_approved", titulo_anuncio: "Captação aprovada")
    returned = create(:habitation, :broker_intake, admin_user: admin, codigo: "RETURN-#{SecureRandom.hex(6)}", intake_status: "returned_to_broker", titulo_anuncio: "Captação devolvida")
    internal = create(:habitation, :broker_intake, admin_user: admin, codigo: "INT-#{SecureRandom.hex(6)}", intake_status: "internal", titulo_anuncio: "Captação interna")
    published = create(:habitation, :broker_intake, admin_user: admin, codigo: "PUB-#{SecureRandom.hex(6)}", intake_status: "published", titulo_anuncio: "Captação publicada")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Meus imóveis")
    expect(response.body).to include("Todos")
    expect(response.body).to include("Pendente de revisão")
    expect(response.body).to include(internal.titulo_anuncio)
    expect(response.body).to include(published.titulo_anuncio)
    expect(response.body).not_to include(submitted.titulo_anuncio)
    expect(response.body).not_to include(approved.titulo_anuncio)
    expect(response.body).not_to include(draft.titulo_anuncio)
    expect(response.body).not_to include(returned.titulo_anuncio)
    expect(response.body).not_to include("Disponível internamente")
    expect(response.body).not_to include("Liberado para site")

    get admin_habitations_path(intake_review: "pending", ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(submitted.titulo_anuncio)
    expect(response.body).to include(approved.titulo_anuncio)
    expect(response.body).to include(draft.titulo_anuncio)
    expect(response.body).to include(returned.titulo_anuncio)
    expect(response.body).to include("Rascunho")
    expect(response.body).to include("Em revisão administrativa")
    expect(response.body).to include("Aguardando aceite do corretor")
    expect(response.body).to include("Devolvido ao corretor")
    expect(response.body).not_to include(internal.titulo_anuncio)
    expect(response.body).not_to include(published.titulo_anuncio)

    html = Nokogiri::HTML(response.body)
    draft_card = html.at_css("#habitation_#{draft.id}")
    expect(draft_card.at_css(".ax-property-card__identity").text).to include("Rascunho")
    expect(draft_card.at_css(".ax-property-chip--intake-draft")).to be_present
    expect(draft_card.at_css(".ax-property-card__media").text).not_to include("Rascunho")
    expect(response.body).to include("ax-property-chip--intake-review")
    expect(response.body).to include("ax-property-chip--intake-approved")
    expect(response.body).to include("ax-property-chip--intake-returned")

    get admin_habitations_path(intake_review: "pending", ownership: "all", visualizacao: "tabela")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rascunho")
    expect(response.body).to include("Em revisão administrativa")
    expect(response.body).to include("Aguardando aceite do corretor")
    expect(response.body).to include("Devolvido ao corretor")
    expect(response.body).to include("ax-property-chip--intake-draft")
    expect(response.body).to include("ax-property-chip--intake-review")
    expect(response.body).to include("ax-property-chip--intake-approved")
    expect(response.body).to include("ax-property-chip--intake-returned")
    expect(response.body).not_to include("Disponível internamente")
    expect(response.body).not_to include("Liberado para site")
  end

  it "mostra para o administrativo apenas captações enviadas para revisão, não as aguardando aceite do corretor" do
    manager_profile, administrative_profile = default_administrative_profiles
    administrative = create(:admin_user, profile: manager_profile, horizontal_profile: administrative_profile, name: "Administrativo Revisão")
    submitted = create(:habitation, :broker_intake, admin_user: admin, codigo: "ADM-SUB-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review", titulo_anuncio: "Revisão do administrativo")
    approved = create(:habitation, :broker_intake, admin_user: admin, codigo: "ADM-APP-#{SecureRandom.hex(6)}", intake_status: "admin_approved", titulo_anuncio: "Aguardando corretor aceitar")
    draft = create(:habitation, :broker_intake, admin_user: admin, codigo: "ADM-DRAFT-#{SecureRandom.hex(6)}", intake_status: "draft", titulo_anuncio: "Rascunho do corretor")
    returned = create(:habitation, :broker_intake, admin_user: admin, codigo: "ADM-RETURN-#{SecureRandom.hex(6)}", intake_status: "returned_to_broker", titulo_anuncio: "Devolvido ao corretor")

    sign_in administrative
    get admin_habitations_path(intake_review: "pending", ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(submitted.titulo_anuncio)
    expect(response.body).not_to include(approved.titulo_anuncio)
    expect(response.body).not_to include(draft.titulo_anuncio)
    expect(response.body).not_to include(returned.titulo_anuncio)
  end

  it "permite sair das pendências para Todos sem restaurar o filtro salvo na sessão" do
    pending = create(:habitation, :broker_intake, admin_user: admin, intake_status: "submitted_for_admin_review", titulo_anuncio: "Pendente da sessão")
    published = create(:habitation, :broker_intake, admin_user: admin, intake_status: "published", titulo_anuncio: "Publicado em Todos")

    get admin_habitations_path(intake_review: "pending", ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(pending.titulo_anuncio)
    expect(response.body).to include("intake_review=all")

    get admin_habitations_path(intake_review: "all", ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(published.titulo_anuncio)
    expect(response.body).not_to include(pending.titulo_anuncio)
    expect(response.body).to include('habitations-view-toggle__item is-active')
  end

  it "mostra para o corretor somente suas captações aguardando aceite" do
    broker_profile = default_agent_profile
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

  it "abre novo imóvel como cadastro direto fora do fluxo de revisão" do
    get new_admin_habitation_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('novalidate="novalidate"')
    expect(response.body).to include("Cadastro direto de imóvel")
    expect(response.body).to include("não passa pelo fluxo de captação/revisão")
    expect(response.body).to include("Criar ficha de captação interna")
    expect(response.body).not_to include("Enviar para corretor")
    expect(response.body).not_to include("Salvar Interno")
    expect(response.body).to include("Salvar")
    expect(response.body).to include("Salvar e sair")
  end

  it "permite excluir imóvel por permissão operacional com escopo total, sem exigir Tenant Owner" do
    tenant = Tenant.create!(name: "Tenant delete #{SecureRandom.hex(3)}", slug: "tenant-delete-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Operations delete #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 300,
      permissions: {
        "dashboard" => { "view" => true },
        "imoveis" => { "view" => true, "manage" => true, "scope" => "all" }
      }
    )
    operator = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    habitation = create(:habitation, tenant: tenant, admin_user: operator, codigo: "DEL-ALL-#{SecureRandom.hex(6)}")

    sign_in operator

    expect {
      delete admin_habitation_path(habitation)
    }.to change(Habitation, :count).by(-1)

    expect(response).to redirect_to(admin_habitations_path)
  end

  it "bloqueia exclusão de imóvel para perfil operacional limitado à equipe" do
    tenant = Tenant.create!(name: "Tenant team delete #{SecureRandom.hex(3)}", slug: "tenant-team-delete-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Team operations #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 300,
      permissions: {
        "dashboard" => { "view" => true },
        "imoveis" => { "view" => true, "manage" => true, "scope" => "team" }
      }
    )
    manager = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    habitation = create(:habitation, tenant: tenant, admin_user: manager, codigo: "DEL-TEAM-#{SecureRandom.hex(6)}")

    sign_in manager

    expect {
      delete admin_habitation_path(habitation)
    }.not_to change(Habitation, :count)

    expect(response).to redirect_to(admin_habitations_path)
    expect(flash[:alert]).to eq("Você não tem permissão para excluir imóveis.")
  end

  it "permite publicação em massa por permissão operacional com escopo total" do
    tenant = Tenant.create!(name: "Tenant bulk #{SecureRandom.hex(3)}", slug: "tenant-bulk-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Bulk publisher #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 300,
      permissions: {
        "dashboard" => { "view" => true },
        "imoveis" => { "view" => true, "manage" => true, "scope" => "all" }
      }
    )
    operator = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    habitation = create(:habitation, tenant: tenant, admin_user: operator, codigo: "BULK-ALL-#{SecureRandom.hex(6)}", exibir_no_site_flag: false)

    sign_in operator

    post bulk_publish_admin_habitations_path, params: {
      selected_ids: [habitation.id],
      action_type: "publicar",
      channels: %w[site]
    }

    expect(response).to have_http_status(:ok)
    expect(habitation.reload.exibir_no_site_flag).to be(true)
  end

  it "bloqueia publicação em massa para perfil operacional limitado à equipe" do
    tenant = Tenant.create!(name: "Tenant bulk team #{SecureRandom.hex(3)}", slug: "tenant-bulk-team-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Bulk team #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 300,
      permissions: {
        "dashboard" => { "view" => true },
        "imoveis" => { "view" => true, "manage" => true, "scope" => "team" }
      }
    )
    manager = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    habitation = create(:habitation, tenant: tenant, admin_user: manager, codigo: "BULK-TEAM-#{SecureRandom.hex(6)}", exibir_no_site_flag: false)

    sign_in manager

    post bulk_publish_admin_habitations_path, params: {
      selected_ids: [habitation.id],
      action_type: "publicar",
      channels: %w[site]
    }

    expect(response).to have_http_status(:forbidden)
    expect(habitation.reload.exibir_no_site_flag).to be(false)
  end

  it "exibe ficha interna de captação somente quando o modo é explícito" do
    get new_admin_habitation_path(intake_mode: "paper")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ficha de captação interna")
    expect(response.body).to include('name="intake_mode"')
    expect(response.body).to include('value="paper"')
    expect(response.body).to include("Enviar para corretor")
    expect(response.body).to include("Salvar Interno")
    expect(response.body).to include("Cadastrar imóvel direto")
    expect(response.body).to include("Salvar")
    expect(response.body).to include("Salvar e sair")
  end

  it "cria imóvel direto sem marcar como captação" do
    expect {
      post admin_habitations_path, params: {
        habitation: {
          categoria: "Apartamento",
          status: "Venda",
          tipo: "Unitário",
          nome_empreendimento: "Edifício Direto #{SecureRandom.hex(4)}",
          bloco: "101",
          address_attributes: {
            logradouro: "Rua Direta #{SecureRandom.hex(4)}",
            numero: "10",
            bairro: "Centro",
            cidade: "Balneário Camboriú",
            uf: "SC"
          }
        }
      }
    }.to change(Habitation, :count).by(1)

    habitation = Habitation.order(:created_at).last
    expect(habitation).not_to be_broker_intake
    expect(habitation.intake_origin).to be_blank
  end

  it "cria ficha interna como captação quando o modo paper é enviado" do
    expect {
      post admin_habitations_path, params: {
        intake_mode: "paper",
        habitation: {
          categoria: "Apartamento",
          status: "Venda",
          tipo: "Unitário",
          nome_empreendimento: "Edifício Ficha #{SecureRandom.hex(4)}",
          bloco: "202",
          address_attributes: {
            logradouro: "Rua Ficha #{SecureRandom.hex(4)}",
            numero: "20",
            bairro: "Centro",
            cidade: "Balneário Camboriú",
            uf: "SC"
          }
        }
      }
    }.to change(Habitation.broker_intakes, :count).by(1)

    habitation = Habitation.order(:created_at).last
    expect(habitation).to be_broker_intake
    expect(habitation.intake_status).to eq("draft")
    expect(habitation.exibir_no_site_flag).to eq(false)
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
    expect(response.body).to include("Pertence ao empreendimento")
    expect(response.body).to include("Nome do empreendimento")
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

    expect(response).to have_http_status(:redirect)
    redirect_uri = URI.parse(response.location)
    expect(redirect_uri.path).to eq(edit_admin_habitation_path(development.id))
    redirect_params = Rack::Utils.parse_nested_query(redirect_uri.query)
    expect(redirect_params).to include(
      "return_to" => "/admin/habitations",
      "ownership" => "all",
      "codigo" => "54"
    )
  end

  it "substitui filtro antigo de empreendimento ao pesquisar pelo código" do
    old_development = create(
      :habitation,
      tipo: "Empreendimento",
      categoria: "Empreendimento",
      codigo: "EMP-OLD-#{SecureRandom.hex(4)}",
      nome_empreendimento: "Edifício Capacidade"
    )
    property = create(
      :habitation,
      codigo: "RET-CODE-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel localizado por código",
      nome_empreendimento: "Residencial Correto"
    )

    get admin_habitations_path(ownership: "all", empreendimento_codigo: "name:#{old_development.nome_empreendimento}")
    expect(response).to have_http_status(:ok)

    get search_by_code_admin_habitations_path(codigo: property.codigo)

    expect(response).to have_http_status(:redirect)
    redirect_uri = URI.parse(response.location)
    expect(redirect_uri.path).to eq(edit_admin_habitation_path(property.id))
    redirect_params = Rack::Utils.parse_nested_query(redirect_uri.query)
    expect(redirect_params).to include(
      "return_to" => "/admin/habitations",
      "ownership" => "all",
      "codigo" => property.codigo
    )

    get admin_habitations_path

    expect(response).to redirect_to(admin_habitations_path(ownership: "all", codigo: property.codigo))
  end

  it "filtra código exato no catálogo sem casar códigos parecidos" do
    exact_code = "894#{SecureRandom.random_number(1000..9999)}"
    matching = create(
      :habitation,
      codigo: exact_code,
      titulo_anuncio: "Imóvel com código exato"
    )
    partial_match = create(
      :habitation,
      codigo: "#{exact_code}2",
      titulo_anuncio: "Imóvel com código parecido"
    )

    get admin_habitations_path(ownership: "all", codigo: exact_code)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.titulo_anuncio)
    expect(response.body).not_to include(partial_match.titulo_anuncio)
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

  it "exibe o usuário fake da DWV como captador no card do catálogo" do
    create(:admin_user, tenant: admin.tenant, name: "Dwv - Imóveis Pauta", email: "laudicardoso@gmail.com")
    dwv_property = create(
      :habitation,
      tenant: admin.tenant,
      admin_user: nil,
      codigo: "DWV-CARD-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel DWV sem captador direto",
      imovel_dwv: "Sim"
    )

    get admin_habitations_path(q: dwv_property.codigo)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(dwv_property.titulo_anuncio)
    expect(response.body).to include("Captador:")
    expect(response.body).to include("Dwv - Imóveis Pauta")
  end

  it "exibe o empreendimento abaixo do endereço e acima do captador no card do catálogo" do
    broker = create(:admin_user, tenant: admin.tenant, name: "Adriana Stark")
    habitation = create(
      :habitation,
      tenant: admin.tenant,
      admin_user: broker,
      codigo: "EMP-CARD-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento no edifício",
      nome_empreendimento: "Atlântica Residence",
      address_attributes: {
        logradouro: "Atlântica",
        numero: "1166",
        bairro: "Centro",
        cidade: "Balneário Camboriú",
        uf: "SC"
      }
    )

    get admin_habitations_path(q: habitation.codigo)

    expect(response).to have_http_status(:ok)
    card_text = Nokogiri::HTML(response.body).css(".ax-property-card").find { |node| node.text.include?(habitation.codigo) }.text
    address_index = card_text.index("Atlântica, 1166")
    development_index = card_text.index("Empreendimento: Atlântica Residence")
    captador_index = card_text.index("Captador: Adriana Stark")

    expect(address_index).to be_present
    expect(development_index).to be > address_index
    expect(captador_index).to be > development_index
  end

  it "renderiza todas as fotos do imóvel no fancybox do card e da tabela" do
    habitation = create(
      :habitation,
      tenant: admin.tenant,
      codigo: "GAL-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Apartamento com galeria completa",
      pictures: [
        { "url" => "https://dwvimagesv1.b-cdn.net/spec/galeria-1.jpg" },
        { "url" => "https://dwvimagesv1.b-cdn.net/spec/galeria-2.jpg" },
        { "url" => "https://dwvimagesv1.b-cdn.net/spec/galeria-3.jpg" }
      ]
    )

    get admin_habitations_path(q: habitation.codigo)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    gallery_links = html.css(%(a[data-fancybox="admin-property-card-#{habitation.id}"]))
    expect(gallery_links.map { |node| node["href"] }).to contain_exactly(
      "https://dwvimagesv1.b-cdn.net/spec/galeria-1.jpg",
      "https://dwvimagesv1.b-cdn.net/spec/galeria-2.jpg",
      "https://dwvimagesv1.b-cdn.net/spec/galeria-3.jpg"
    )

    get admin_habitations_path(q: habitation.codigo, visualizacao: "tabela")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    gallery_links = html.css(%(a[data-fancybox="admin-property-row-#{habitation.id}"]))
    expect(gallery_links.map { |node| node["href"] }).to contain_exactly(
      "https://dwvimagesv1.b-cdn.net/spec/galeria-1.jpg",
      "https://dwvimagesv1.b-cdn.net/spec/galeria-2.jpg",
      "https://dwvimagesv1.b-cdn.net/spec/galeria-3.jpg"
    )
  end

  it "não exibe badge de canais publicados no card do catálogo" do
    habitation = create(
      :habitation,
      tenant: admin.tenant,
      codigo: "PUB-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel publicado sem badge de canais",
      exibir_no_site_flag: true,
      publicar_imovelweb: true,
      publicar_viva_real_vrsync: true
    )

    get admin_habitations_path(q: habitation.codigo)

    expect(response).to have_http_status(:ok)
    card = Nokogiri::HTML(response.body).css(".ax-property-card").find { |node| node.text.include?(habitation.codigo) }
    expect(card).to be_present
    expect(card.text).not_to include("Publicado em")
    expect(card.text).not_to include("PUBLICADO EM")
  end

  it "não inclui imóveis apenas vinculados como corretor secundário em Meus imóveis" do
    broker_profile = default_agent_profile
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
    broker_profile = default_agent_profile
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
    card = Nokogiri::HTML(response.body).css(".ax-property-card").find { |node| node.text.include?(other_property.codigo) }
    expect(card).to be_present
    expect(card["style"].to_s).not_to include("height: 240px")
    expect(response.body).to include(CGI.escapeHTML("#{admin_habitation_path(other_property.id)}?return_to=/admin/habitations&ownership=all&q=#{other_property.codigo}&back_anchor=habitation_#{other_property.id}"))
    expect(response.body).not_to include(%(data-clickable-card-url-value="#{CGI.escapeHTML(habitation_path(other_property))}"))

    get admin_habitation_path(other_property, return_to: admin_habitations_path(ownership: "all", q: other_property.codigo))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Resumo do imóvel")
    expect(response.body).to include("Dados principais")
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
    broker_profile = default_agent_profile
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
    expect(response.body).to include(CGI.escapeHTML("#{admin_habitation_path(own_property.id)}?return_to=/admin/habitations&ownership=all&q=#{own_property.codigo}&back_anchor=habitation_#{own_property.id}"))
    expect(response.body).to include(CGI.escapeHTML("#{edit_admin_habitation_path(own_property.id)}?return_to=/admin/habitations&ownership=all&q=#{own_property.codigo}&back_anchor=habitation_#{own_property.id}"))
  end

  it "permite que corretor filtre imóveis por colegas da mesma conta no catálogo" do
    broker_profile = default_agent_profile
    luciana = create(:admin_user, profile: broker_profile, name: "Luciana Filtro")
    patricia = create(:admin_user, profile: broker_profile, name: "Patrícia Filtro")
    other_tenant = Tenant.create!(name: "Outra conta filtros #{SecureRandom.hex(4)}", slug: "outra-conta-filtros-#{SecureRandom.hex(4)}")
    outside_broker = create(:admin_user, tenant: other_tenant, name: "Corretor Outra Conta")
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
    outside_property = create(
      :habitation,
      tenant: other_tenant,
      admin_user: outside_broker,
      codigo: "FILTRO-OUTSIDE-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel de outra conta no filtro"
    )

    sign_in luciana
    get filter_inspector_admin_habitations_path(ownership: "all"), headers: turbo_frame_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="corretor_id"')
    expect(response.body).to include("Luciana Filtro")
    expect(response.body).to include("Patrícia Filtro")
    expect(response.body).not_to include("Corretor Outra Conta")
    expect(response.body).not_to include('name="proprietor_id"')

    get admin_habitations_path(ownership: "mine", corretor_id: patricia.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(own_property.titulo_anuncio)
    expect(response.body).to include(other_property.titulo_anuncio)
    expect(response.body).not_to include(outside_property.titulo_anuncio)

    get admin_habitations_path(ownership: "mine", corretor_id: outside_broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_property.titulo_anuncio)
    expect(response.body).not_to include(other_property.titulo_anuncio)
    expect(response.body).not_to include(outside_property.titulo_anuncio)
  end

  it "permite filtro de corretor de imóveis por colegas fora da subárvore no catálogo" do
    tenant = admin.tenant
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Imóveis #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 700,
      permissions: {
        "dashboard" => { "view" => true },
        "imoveis" => { "view" => true, "manage" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: admin, name: "Gestor Imóveis")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Subordinado Imóveis")
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: admin, name: "Par Imóveis")
    manager_property = create(:habitation, tenant: tenant, admin_user: manager, codigo: "GESTOR-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel do gestor")
    subordinate_property = create(:habitation, tenant: tenant, admin_user: subordinate, codigo: "SUB-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel do subordinado")
    peer_property = create(:habitation, tenant: tenant, admin_user: peer, codigo: "PEER-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel do par")

    sign_in manager

    get filter_inspector_admin_habitations_path(ownership: "all"), headers: turbo_frame_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Gestor Imóveis")
    expect(response.body).to include("Subordinado Imóveis")
    expect(response.body).to include("Par Imóveis")

    get admin_habitations_path(ownership: "mine", corretor_id: peer.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(manager_property.titulo_anuncio)
    expect(response.body).not_to include(subordinate_property.titulo_anuncio)
    expect(response.body).to include(peer_property.titulo_anuncio)
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

  it "ordena 'Mais recentes' pela última atividade humana e ignora sincronizações técnicas" do
    human_edited = create(
      :habitation,
      codigo: "8826",
      titulo_anuncio: "Imóvel alterado por humano",
      data_cadastro_crm: 10.days.ago,
      updated_at: 2.days.ago
    )
    synced_by_dwv = create(
      :habitation,
      codigo: "9999",
      titulo_anuncio: "Imóvel sincronizado pelo DWV",
      data_cadastro_crm: 1.hour.from_now,
      data_atualizacao_crm: 3.hours.from_now,
      last_sync_at: 3.hours.from_now,
      updated_at: 3.hours.from_now
    )
    create(:habitation_audit_log, habitation: human_edited, admin_user: admin, source: "admin", created_at: 2.hours.from_now)
    create(:habitation_audit_log, habitation: synced_by_dwv, admin_user: admin, source: "integracao", created_at: 3.hours.from_now)

    get admin_habitations_path(sort: "data_cadastro_crm", direction: "desc")

    expect(response).to have_http_status(:ok)
    expect(response.body.index(human_edited.titulo_anuncio)).to be < response.body.index(synced_by_dwv.titulo_anuncio)
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
    centro = create(:habitation, codigo: "BAIRRO-CENTRO-#{SecureRandom.hex(4)}", titulo_anuncio: "Imóvel bairro Centro").tap { |habitation| habitation.address.update!(bairro: "Centro") }
    barra = create(:habitation, codigo: "BAIRRO-BARRA-#{SecureRandom.hex(4)}", titulo_anuncio: "Imóvel bairro Barra Sul").tap { |habitation| habitation.address.update!(bairro: "Barra Sul") }
    outro = create(:habitation, codigo: "BAIRRO-OUTRO-#{SecureRandom.hex(4)}", titulo_anuncio: "Imóvel bairro Outro").tap { |habitation| habitation.address.update!(bairro: "Nações") }

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
    standalone_unit_same_name = create(
      :habitation,
      codigo: "PREDIO-UNIT-#{SecureRandom.hex(6)}",
      tipo: "Unitário",
      codigo_empreendimento: nil,
      nome_empreendimento: "residencial sem cadastro",
      titulo_anuncio: "Unidade com prédio direto em caixa baixa"
    )
    other_property = create(
      :habitation,
      codigo: "PREDIO-OTHER-#{SecureRandom.hex(6)}",
      tipo: "Unitário",
      codigo_empreendimento: nil,
      nome_empreendimento: "Outro Prédio",
      titulo_anuncio: "Outro imóvel"
    )

    get filter_inspector_admin_habitations_path, headers: turbo_frame_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Residencial Sem Cadastro")

    get admin_habitations_path(empreendimento_codigo: "name:Residencial Sem Cadastro")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(standalone_unit.titulo_anuncio)
    expect(response.body).to include(standalone_unit_same_name.titulo_anuncio)
    expect(response.body).not_to include(other_property.titulo_anuncio)

    get admin_habitations_path(empreendimento_codigo: "Residencial Sem Cadastro")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(standalone_unit.titulo_anuncio)
    expect(response.body).to include(standalone_unit_same_name.titulo_anuncio)
    expect(response.body).not_to include(other_property.titulo_anuncio)
  end

  it "filtra empreendimento por corretor sem erro de distinct com ordenação" do
    broker = create(:admin_user, name: "Laudi Cardoso")
    development_code = "DEV-BROKER-#{SecureRandom.hex(6)}"
    create(:habitation, codigo: development_code, tipo: "Empreendimento", nome_empreendimento: "Residencial Broker")
    matching = create(
      :habitation,
      codigo: "EMP-BROKER-#{SecureRandom.hex(6)}",
      codigo_empreendimento: development_code,
      titulo_anuncio: "Imóvel do corretor filtrado",
      address_attributes: {
        logradouro: "Rua Empreendimento",
        numero: "183",
        bairro: "Centro",
        cidade: "Balneário Camboriú",
        uf: "SC"
      }
    )
    other_property = create(
      :habitation,
      codigo: "EMP-OTHER-#{SecureRandom.hex(6)}",
      codigo_empreendimento: development_code,
      titulo_anuncio: "Imóvel de outro corretor",
      address_attributes: {
        logradouro: "Rua Empreendimento",
        numero: "184",
        bairro: "Centro",
        cidade: "Balneário Camboriú",
        uf: "SC"
      }
    )
    matching.broker_assignments.create!(admin_user: broker, role: "captador")

    get admin_habitations_path(empreendimento_codigo: "dev:#{development_code}", corretor_id: broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.titulo_anuncio)
    expect(response.body).to include("Empreendimento: Residencial Broker")
    expect(response.body).not_to include(other_property.titulo_anuncio)

    get admin_habitations_path(empreendimento_codigo: development_code, corretor_id: broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.titulo_anuncio)
    expect(response.body).not_to include(other_property.titulo_anuncio)
  end

  it "preserva filtros da listagem ao editar e salvar saindo" do
    habitation = create(:habitation, codigo: "RET-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel com retorno")
    habitation.address.update!(
      logradouro: "Rua Retorno",
      numero: "123",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    return_path = admin_habitations_path(q: habitation.codigo, status: habitation.status)

    get return_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML("#{edit_admin_habitation_path(habitation.id)}?return_to=/admin/habitations&q=#{habitation.codigo}&status=#{habitation.status}&back_anchor=habitation_#{habitation.id}"))

    get edit_admin_habitation_path(habitation.id, return_to: return_path)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ERB::Util.html_escape(return_path))
    edit_html = Nokogiri::HTML(response.body)
    authenticity_token =
      edit_html.at_css(%(input[name="authenticity_token"]))&.[]("value") ||
      edit_html.at_css(%(meta[name="csrf-token"]))&.[]("content")
    expect(authenticity_token).to be_present

    patch admin_habitation_path(habitation.id), params: {
      authenticity_token: authenticity_token,
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
    }, headers: { "X-CSRF-Token" => authenticity_token }

    expect(response).to redirect_to(return_path)
  end

  it "preserva filtros avançados ao abrir o imóvel pelo catálogo e voltar" do
    habitation = create(
      :habitation,
      codigo: "RET-ADV-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel com retorno avançado",
      nome_empreendimento: "Vermont",
      categoria: "Apartamento",
      status: "Venda"
    )
    return_path = admin_habitations_path(
      ownership: "all",
      empreendimento_codigo: "name:Vermont",
      corretor_id: "",
      status: "",
      categoria: "",
      visualizacao: "tabela"
    )

    get return_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    card_link = html.at_css(%([data-clickable-card-url-value*="/admin/habitations/#{habitation.id}/edit"]))
    expect(card_link).to be_present
    card_url = CGI.unescapeHTML(card_link["data-clickable-card-url-value"])
    expect(card_url).to include(edit_admin_habitation_path(habitation.id))
    expect(card_url).to include("return_to=/admin/habitations")
    expect(card_url).to include("ownership=all")
    expect(card_url).to include("empreendimento_codigo=name%3AVermont")
    expect(card_url).to include("visualizacao=tabela")
    expect(card_url).to include("back_anchor=habitation_#{habitation.id}")

    get admin_habitation_path(
      habitation.id,
      return_to: "/admin/habitations",
      ownership: "all",
      empreendimento_codigo: "name:Vermont",
      visualizacao: "tabela",
      back_anchor: "habitation_#{habitation.id}"
    )

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    back_link = html.css("a").select { |node| node.text.squish == "Voltar" }.find do |node|
      CGI.unescapeHTML(node["href"].to_s).include?("empreendimento_codigo=")
    end
    expect(back_link).to be_present

    back_href = CGI.unescapeHTML(back_link["href"])
    back_uri = URI.parse(back_href)
    back_params = Rack::Utils.parse_nested_query(back_uri.query)

    expect(back_uri.path).to eq(admin_habitations_path)
    expect(back_params).to include(
      "ownership" => "all",
      "empreendimento_codigo" => "name:Vermont",
      "visualizacao" => "tabela"
    )
    expect(back_uri.fragment).to eq("habitation_#{habitation.id}")
  end

  it "preserva página e card de origem ao abrir, voltar e salvar saindo do imóvel" do
    habitations = (1..11).map do |index|
      create(
        :habitation,
        codigo: "RET-PAGE-#{index.to_s.rjust(2, '0')}",
        titulo_anuncio: "Imóvel paginado #{index}",
        categoria: "Apartamento",
        status: "Venda"
      ).tap do |habitation|
        habitation.address.update!(
          logradouro: "Rua Página",
          numero: index.to_s,
          bairro: "Centro",
          cidade: "Balneário Camboriú",
          uf: "SC"
        )
      end
    end
    target = habitations.last
    page_path = admin_habitations_path(
      ownership: "all",
      page: 2,
      per_page: 10,
      sort: "codigo",
      direction: "asc"
    )

    get page_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    card_link = html.at_css(%([data-clickable-card-url-value*="/admin/habitations/#{target.id}/edit"]))
    expect(card_link).to be_present
    card_url = CGI.unescapeHTML(card_link["data-clickable-card-url-value"])
    expect(card_url).to include("return_to=/admin/habitations")
    expect(card_url).to include("page=2")
    expect(card_url).to include("per_page=10")
    expect(card_url).to include("sort=codigo")
    expect(card_url).to include("direction=asc")
    expect(card_url).to include("back_anchor=habitation_#{target.id}")

    get admin_habitation_path(
      target.id,
      return_to: "/admin/habitations",
      ownership: "all",
      page: "2",
      per_page: "10",
      sort: "codigo",
      direction: "asc",
      back_anchor: "habitation_#{target.id}"
    )

    expect(response).to have_http_status(:ok)
    show_html = Nokogiri::HTML(response.body)
    breadcrumb_back_link = show_html.at_css("a.ax-breadcrumb__back")
    expect(breadcrumb_back_link).to be_present
    breadcrumb_back_uri = URI.parse(CGI.unescapeHTML(breadcrumb_back_link["href"]))
    breadcrumb_back_params = Rack::Utils.parse_nested_query(breadcrumb_back_uri.query)
    expect(breadcrumb_back_uri.path).to eq(admin_habitations_path)
    expect(breadcrumb_back_params).to include(
      "ownership" => "all",
      "page" => "2",
      "per_page" => "10",
      "sort" => "codigo",
      "direction" => "asc"
    )
    expect(breadcrumb_back_uri.fragment).to eq("habitation_#{target.id}")

    back_link = show_html.css("a").select { |node| node.text.squish == "Voltar" }.find do |node|
      CGI.unescapeHTML(node["href"].to_s).include?("page=2")
    end
    expect(back_link).to be_present
    back_uri = URI.parse(CGI.unescapeHTML(back_link["href"]))
    back_params = Rack::Utils.parse_nested_query(back_uri.query)
    expect(back_uri.path).to eq(admin_habitations_path)
    expect(back_params).to include(
      "ownership" => "all",
      "page" => "2",
      "per_page" => "10",
      "sort" => "codigo",
      "direction" => "asc"
    )
    expect(back_uri.fragment).to eq("habitation_#{target.id}")

    get edit_admin_habitation_path(
      target.id,
      return_to: "/admin/habitations",
      ownership: "all",
      page: "2",
      per_page: "10",
      sort: "codigo",
      direction: "asc",
      back_anchor: "habitation_#{target.id}"
    )
    expect(response).to have_http_status(:ok)
    edit_html = Nokogiri::HTML(response.body)
    edit_breadcrumb_back_link = edit_html.at_css("a.ax-breadcrumb__back")
    expect(edit_breadcrumb_back_link).to be_present
    edit_breadcrumb_back_uri = URI.parse(CGI.unescapeHTML(edit_breadcrumb_back_link["href"]))
    edit_breadcrumb_back_params = Rack::Utils.parse_nested_query(edit_breadcrumb_back_uri.query)
    expect(edit_breadcrumb_back_uri.path).to eq(admin_habitations_path)
    expect(edit_breadcrumb_back_params).to include(
      "ownership" => "all",
      "page" => "2",
      "per_page" => "10",
      "sort" => "codigo",
      "direction" => "asc"
    )
    expect(edit_breadcrumb_back_uri.fragment).to eq("habitation_#{target.id}")

    authenticity_token =
      edit_html.at_css(%(input[name="authenticity_token"]))&.[]("value") ||
      edit_html.at_css(%(meta[name="csrf-token"]))&.[]("content")
    expect(authenticity_token).to be_present

    patch admin_habitation_path(target.id), params: {
      authenticity_token: authenticity_token,
      return_to: "/admin/habitations",
      ownership: "all",
      page: "2",
      per_page: "10",
      sort: "codigo",
      direction: "asc",
      back_anchor: "habitation_#{target.id}",
      save_navigation: "exit",
      habitation: {
        titulo_anuncio: "Imóvel paginado atualizado",
        address_attributes: {
          id: target.address.id,
          logradouro: "Rua Página",
          numero: target.address.numero,
          bairro: "Centro",
          cidade: "Balneário Camboriú",
          uf: "SC"
        }
      }
    }, headers: { "X-CSRF-Token" => authenticity_token }

    expect(response).to have_http_status(:found)
    redirect_uri = URI.parse(response.location)
    redirect_params = Rack::Utils.parse_nested_query(redirect_uri.query)
    expect(redirect_uri.path).to eq(admin_habitations_path)
    expect(redirect_params).to include(
      "ownership" => "all",
      "page" => "2",
      "per_page" => "10",
      "sort" => "codigo",
      "direction" => "asc"
    )
    expect(redirect_uri.fragment).to eq("habitation_#{target.id}")
  end

  it "restaura o último filtro do catálogo ao voltar para imóveis sem query string" do
    habitation = create(
      :habitation,
      codigo: "RET-SESSION-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel com filtro persistido",
      nome_empreendimento: "Vermont",
      categoria: "Apartamento",
      status: "Venda"
    )
    filtered_path = admin_habitations_path(
      ownership: "all",
      empreendimento_codigo: "name:Vermont",
      visualizacao: "tabela"
    )

    get filtered_path
    expect(response).to have_http_status(:ok)

    get admin_habitation_path(habitation)
    expect(response).to have_http_status(:ok)

    get admin_habitations_path

    expect(response).to redirect_to(filtered_path)
  end

  it "restaura o último filtro quando a navegação volta para imóveis só com parâmetros neutros" do
    habitation = create(
      :habitation,
      codigo: "RET-NEUTRAL-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel com filtro persistido por navegação",
      nome_empreendimento: "Vermont",
      categoria: "Apartamento",
      status: "Venda"
    )
    filtered_path = admin_habitations_path(
      ownership: "all",
      empreendimento_codigo: "name:Vermont"
    )

    get filtered_path
    expect(response).to have_http_status(:ok)

    get admin_habitation_path(habitation)
    expect(response).to have_http_status(:ok)

    get admin_habitations_path(ownership: "all")

    expect(response).to redirect_to(filtered_path)
  end

  it "não restaura o filtro salvo quando a navegação informa uma página específica" do
    create(
      :habitation,
      codigo: "RET-PAGE-SESSION-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel com filtro salvo",
      nome_empreendimento: "Vermont",
      categoria: "Apartamento",
      status: "Venda"
    )
    filtered_path = admin_habitations_path(ownership: "all", empreendimento_codigo: "name:Vermont")

    get filtered_path
    expect(response).to have_http_status(:ok)

    get admin_habitations_path(ownership: "all", page: 2)

    expect(response).to have_http_status(:ok)
  end

  it "limpa o último filtro do catálogo quando o usuário pede para limpar filtros" do
    create(
      :habitation,
      codigo: "RET-CLEAR-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Imóvel com filtro para limpar",
      nome_empreendimento: "Vermont"
    )
    filtered_path = admin_habitations_path(ownership: "all", empreendimento_codigo: "name:Vermont")

    get filtered_path
    expect(response).to have_http_status(:ok)

    get admin_habitations_path(ownership: "all", clear_filters: "1")
    expect(response).to redirect_to(admin_habitations_path(ownership: "all"))

    get admin_habitations_path
    expect(response).to have_http_status(:ok)
  end

  it "remove filtros vazios do retorno para manter a URL do cadastro enxuta" do
    habitation = create(:habitation, codigo: "RET-LIMPO-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel com retorno limpo")
    noisy_return_path = "/admin/habitations?ownership=all&q=#{CGI.escape(habitation.codigo)}&bairro=&status=&dorms%5B%5D=&vagas%5B%5D="
    clean_return_path = admin_habitations_path(ownership: "all", q: habitation.codigo)

    get noisy_return_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML("#{edit_admin_habitation_path(habitation.id)}?return_to=/admin/habitations&ownership=all&q=#{habitation.codigo}&back_anchor=habitation_#{habitation.id}"))
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
    card = Nokogiri::HTML(response.body).css(".ax-property-card").find { |node| node.text.include?(inactive.codigo) }
    expect(card).to be_present
    expect(card["class"]).to include("property-card--inactive")
  end

  it "não marca imóvel ativo fora do site como card cinza" do
    internal = create(:habitation, codigo: "INTERNO-#{SecureRandom.hex(6)}", status: "Aluguel", exibir_no_site_flag: false, titulo_anuncio: "Imóvel interno ativo")

    get admin_habitations_path(q: internal.codigo)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Fora site")
    card = Nokogiri::HTML(response.body).css(".ax-property-card").find { |node| node.text.include?(internal.codigo) }
    expect(card).to be_present
    expect(card["class"]).not_to include("property-card--inactive")
  end

  it "limpa filtros do estado vazio voltando para Todos os imóveis" do
    get admin_habitations_path(ownership: "mine", q: "sem-resultado-#{SecureRandom.hex(8)}")

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    clear_link = document.at_css(".ax-property-empty a.ax-btn")

    expect(response.body).to include("Nenhum imóvel encontrado")
    expect(clear_link.text).to include("Limpar filtros")
    expect(clear_link["href"]).to eq(admin_habitations_path(ownership: "all"))
  end

  it "renderiza controles compactos do catálogo para mobile sem remover o bloco desktop" do
    create(:habitation, codigo: "MOBILE-CATALOG-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel para controles mobile")

    get admin_habitations_path(ownership: "all", min_price: "1400000")

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    mobile_summary = document.at_css(".habitations-mobile-catalog-summary")
    mobile_sort = document.at_css(".habitations-mobile-sort-controls")
    desktop_heading = document.at_css(".habitations-workspace-heading")

    expect(mobile_summary.text).to include("total")
    expect(mobile_summary.text).to include("filtrados")
    expect(mobile_summary.text.index("total")).to be < mobile_summary.text.index("filtrados")
    expect(mobile_summary.at_css(".habitations-mobile-catalog-summary__item")).to be_nil
    expect(mobile_sort.text).to include("Ordenar:")
    expect(mobile_sort.at_css("[data-controller='ax-dropdown']")).to be_present
    expect(mobile_sort.at_css("[data-action*='ax-dropdown#toggle']")).to be_present
    expect(mobile_sort.at_css("[data-ax-dropdown-target='menu']")).to be_present
    expect(desktop_heading.text).to include("Catálogo operacional")
  end

  it "renderiza o catálogo em workspace com sidebar global e filtros no inspector" do
    create(:habitation, codigo: "LAYOUT-#{SecureRandom.hex(6)}", titulo_anuncio: "Imóvel para layout master detail")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{<aside class="ax-sidebar"})
    expect(response.body).to match(%r{<body class="[^"]*\bax-habitations-workspace\b})
    expect(response.body).not_to match(%r{<body class="[^"]*\badmin-drawer-catalog-layout\b})
    expect(response.body).not_to match(%r{<body class="[^"]*\bax-catalog-layout\b})
    expect(response.body).to match(/class="[^"]*\bhabitations-master-detail-layout\b[^"]*"/)
    expect(response.body).to include('data-controller="ax-aside"')
    expect(response.body).to match(/class="[^"]*\bhabitations-detail-pane\b[^"]*"/)
    expect(response.body).to match(/class="[^"]*\bhabitations-master-pane\b[^"]*"/)
    expect(response.body).to include("Filtros do catálogo")
    expect(response.body).to match(/class="[^"]*\bhabitations-inspector-rail\b[^"]*"/)
    expect(response.body).to include('data-action="click-&gt;ax-aside#toggle"')
    expect(response.body).not_to include("PROPERTY_QUERY")
    expect(response.body).not_to include(">Inspector<")
  end

  it "renderiza filtros rápidos dentro do inspector de filtros do catálogo" do
    get filter_inspector_admin_habitations_path(scope: "frente_mar"), headers: turbo_frame_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Filtros rápidos")
    expect(response.body).to match(/class="[^"]*\bhabitations-scope-strip--inspector\b[^"]*"/)
    expect(response.body).to include("Frente Mar")
    expect(response.body).to include("is-active")
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
      expect(response.body).to include(Admin::HabitationsController::REPORT_TYPES.fetch(report_type))
    end
  end

  it "salva o imóvel completo e libera a captação para o corretor publicar" do
    intake = create(:habitation, :broker_intake, admin_user: admin, codigo: "REL-#{SecureRandom.hex(6)}", intake_status: "submitted_for_admin_review")
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Central",
      numero: "100",
      complemento: "Casa 12",
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
      complemento: "Casa 14",
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
      complemento: "Casa 15",
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
      complemento: "Casa 20",
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
    expect(response.body).to include("Autorizações de venda")
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

    get modal_admin_habitation_media_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Classificação das fotos")
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
    direct_upload_io = StringIO.new("foto enviada direto")
    direct_upload_io.rewind
    blob = ActiveStorage::Blob.create_and_upload!(
      io: direct_upload_io,
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
    direct_upload_io = StringIO.new("foto enviada direto")
    direct_upload_io.rewind
    blob = ActiveStorage::Blob.create_and_upload!(
      io: direct_upload_io,
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

  it "exibe só as fotos anexadas na edição (fonte única: Vista/API fora do manager)" do
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

    get modal_admin_habitation_media_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("local.jpg")
    # Vista fora: fotos da API/Vista não são mais renderizadas no manager.
    expect(response.body).not_to include("https://example.com/api-visivel.jpg")
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
    expect(response.body).to include("data-save-state-target=\"modal\"")
    expect(response.body).to include("data-action=\"save-state#submitStay\"")
    expect(response.body).to include("data-action=\"save-state#submitExit\"")
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
    broker_profile = default_agent_profile
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
    manager_profile, administrative_profile = default_administrative_profiles
    administrative_user = create(:admin_user, profile: manager_profile, horizontal_profile: administrative_profile)
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
    expect(response.body).to include("Autorizações de venda")
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
    broker_profile = default_agent_profile
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
    broker_profile = default_agent_profile
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
      pictures: [{ "url" => "https://imob.sfo3.cdn.digitaloceanspaces.com/spec/foto-api-show.jpg" }]
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
    expect(response.body).to include("https://imob.sfo3.cdn.digitaloceanspaces.com/spec/foto-api-show.jpg")
    expect(response.body).to include("data-fancybox")
    expect(response.body).to include("Dados principais")
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
    broker_profile = default_agent_profile
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
    expect(response.body).to include("Editar")
    expect(response.body).not_to include("Proprietário do Captador")
    expect(response.body).not_to include("proprietario@example.com")
    expect(response.body).not_to include("Anexos e documentos internos")
    expect(response.body).not_to include("ficha-captador.txt")
  end

  it "bloqueia campos sensíveis para corretor ao editar imóvel atribuído" do
    broker_profile = default_agent_profile
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

    expect(response).to redirect_to("#{edit_admin_habitation_path(habitation.id)}?return_to=/admin/habitations&ownership=all&q=#{habitation.codigo}#documents")
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
