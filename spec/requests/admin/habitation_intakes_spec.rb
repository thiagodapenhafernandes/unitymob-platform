require "rails_helper"
require "csv"

RSpec.describe "Admin::HabitationIntakes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

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

  it "abre nova captação sem criar rascunho automaticamente" do
    expect {
      get new_admin_captacao_path
    }.not_to change { Habitation.broker_intakes.count }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sem rascunho criado")
    expect(response.body).to include("Iniciar captação")
    expect(response.body).to include("Tipo de cadastro")
    expect(response.body).to include("Comerciais e industriais")
    expect(response.body).to include("Categoria relacionada")
  end

  it "vincula a nova captação à versão e às regras vigentes da política" do
    setting = PropertySetting.instance(tenant: admin.tenant)
    setting.update!(
      review_policy_version: 4,
      broker_capture_layer_enabled: true,
      required_broker_intake_checks: %w[proprietario endereco fotos]
    )

    post admin_captacoes_path

    intake = admin.tenant.habitations.broker_intakes.order(:id).last
    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "proprietario"))
    expect(intake).to have_attributes(intake_review_policy_version: 4)
    expect(intake.intake_review_policy_snapshot).to include(
      "version" => 4,
      "broker_capture_layer_enabled" => true,
      "required_broker_intake_checks" => %w[proprietario endereco fotos]
    )

    setting.update!(review_policy_version: 5, required_broker_intake_checks: %w[titulo])
    expect(intake.reload.effective_intake_review_checks(fallback_setting: setting)).to eq(%w[proprietario endereco fotos])
  end

  it "exibe exportador de planilha somente para administrador ou administrativo" do
    get admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Exportar")

    broker_profile = default_agent_profile
    broker = create(:admin_user, profile: broker_profile)
    sign_in broker

    get admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Exportar")
  end

  it "exibe mini dashboard com totais das captações visíveis" do
    create(:habitation, :broker_intake, admin_user: admin, codigo: "CAP-#{SecureRandom.hex(4)}", intake_status: "draft", intake_modalidade: "venda", categoria: "Apartamento")
    create(:habitation, :broker_intake, admin_user: admin, codigo: "CAP-#{SecureRandom.hex(4)}", intake_status: "returned_to_broker", intake_modalidade: "locacao_anual", categoria: "Sala Comercial")
    create(:habitation, :broker_intake, admin_user: admin, codigo: "CAP-#{SecureRandom.hex(4)}", intake_status: "submitted_for_admin_review", intake_modalidade: "ambos", categoria: "Terreno")
    create(:habitation, :broker_intake, admin_user: admin, codigo: "CAP-#{SecureRandom.hex(4)}", intake_status: "admin_approved", intake_modalidade: "locacao_diaria", categoria: "Apartamento")
    create(:habitation, :broker_intake, admin_user: admin, codigo: "CAP-#{SecureRandom.hex(4)}", intake_status: "published", intake_modalidade: "venda", categoria: "Apartamento", exibir_no_site_flag: true)

    get admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Total")
    expect(response.body).to include("Rascunhos")
    expect(response.body).to include("Em revisão")
    expect(response.body).to include("Aprovadas")
    expect(response.body).to include("Publicadas")
    expect(response.body).to include("Devolvidas")
    expect(response.body).to include("Residencial: 3")
    expect(response.body).to include("Comercial: 1")
    expect(response.body).to include("Terreno: 1")
  end

  it "não conta captação com fotos anexadas como sem fotos" do
    create(:habitation, :broker_intake, admin_user: admin, pictures: [])
    with_attachment = create(:habitation, :broker_intake, admin_user: admin, pictures: [])
    with_attachment.photos.attach(
      io: StringIO.new("foto"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )

    get admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sem fotos")
    expect(response.body).to include("1 sem fotos")
  end

  it "mantém rascunho de ficha de papel visível somente para quem começou" do
    manager_profile, administrative_profile = default_administrative_profiles
    creator = create(:admin_user, profile: manager_profile, horizontal_profile: administrative_profile, name: "Administrativo Criador")
    other = create(:admin_user, profile: manager_profile, horizontal_profile: administrative_profile, name: "Administrativo Outro")
    own_draft = create(:habitation, :broker_intake, admin_user: creator, intake_status: "draft", titulo_anuncio: "Rascunho do criador")
    other_draft = create(:habitation, :broker_intake, admin_user: other, intake_status: "draft", titulo_anuncio: "Rascunho de outro usuário")
    submitted = create(:habitation, :broker_intake, admin_user: other, intake_status: "submitted_for_admin_review", titulo_anuncio: "Ficha em revisão")

    sign_in creator
    get admin_captacoes_path(status: "draft")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_draft.titulo_anuncio)
    expect(response.body).not_to include(other_draft.titulo_anuncio)

    get admin_captacoes_path

    expect(response.body).to include(submitted.titulo_anuncio)
  end

  it "oculta captações internas/publicadas da lista padrão e filtra por corretor para perfis autorizados" do
    first_broker = create(:admin_user, name: "Corretor Alfa")
    second_broker = create(:admin_user, name: "Corretor Beta")
    first_visible = create(:habitation, :broker_intake, admin_user: first_broker, intake_status: "submitted_for_admin_review", titulo_anuncio: "Captação Alfa em revisão")
    second_visible = create(:habitation, :broker_intake, admin_user: second_broker, intake_status: "admin_approved", titulo_anuncio: "Captação Beta aprovada")
    internal = create(:habitation, :broker_intake, admin_user: first_broker, intake_status: "internal", titulo_anuncio: "Captação Alfa interna")
    published = create(:habitation, :broker_intake, admin_user: first_broker, intake_status: "published", titulo_anuncio: "Captação Alfa publicada")

    get admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="corretor_id"')
    expect(response.body).to include(first_visible.titulo_anuncio)
    expect(response.body).to include(second_visible.titulo_anuncio)
    expect(response.body).not_to include(internal.titulo_anuncio)
    expect(response.body).not_to include(published.titulo_anuncio)

    get admin_captacoes_path(corretor_id: first_broker.id)

    expect(response.body).to include(first_visible.titulo_anuncio)
    expect(response.body).not_to include(second_visible.titulo_anuncio)
  end

  it "usa rótulos claros para enviar análise e publicar no site pelo captador" do
    broker_profile = default_agent_profile
    broker = create(:admin_user, profile: broker_profile)
    intake = create(:habitation, :broker_intake, admin_user: broker, intake_step: "review", intake_status: "draft")

    sign_in broker
    get edit_admin_captacao_path(intake, step: "review")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Mandar Análise")
    expect(response.body).to include("vai para revisão administrativa")
    expect(response.body).to include("disponível para você publicar no site")
    expect(response.body).not_to include("Finalizar captação")
    expect(response.body).not_to include("disponível para publicação no site pelo admin")

    intake.update!(intake_status: "admin_approved")
    get admin_captacao_path(intake)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Publicar Site")
    expect(response.body).not_to include("Marcar como publicada")

    sign_in admin
    get admin_captacao_path(intake)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Publicar Site")
  end

  it "exibe campo auxiliar para buscar proprietário por código na etapa do PWA" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "proprietario")

    get edit_admin_captacao_path(intake, step: "proprietario")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Código do proprietário")
    expect(response.body).to include('data-proprietor-lookup-target="code"')
  end

  it "sugere cidades de proprietários já cadastrados na etapa do PWA" do
    create(:proprietor, city: "Itajaí")
    create(:proprietor, city: "Balneário Camboriú")
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "proprietario")

    get edit_admin_captacao_path(intake, step: "proprietario")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-autocomplete-select")
    expect(response.body).to include('data-controller="tom-select"')
    expect(response.body).to include('data-tom-select-create-value="true"')
    expect(response.body).to include('value="Itajaí"')
    expect(response.body).to include('value="Balneário Camboriú"')
  end

  it "localiza proprietário pelo código para autocompletar a captação" do
    proprietor = create(
      :proprietor,
      name: "Thiago Proprietário",
      vista_code: "PROP-9044",
      cpf_cnpj: "123.456.789-00",
      mobile_phone: "(21) 99087-2427",
      email: "thiago@example.com",
      city: "Itajaí"
    )

    get proprietor_lookup_admin_captacoes_path, params: { code: "PROP-9044" }, as: :json

    payload = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(payload).to include("found" => true, "matched_by" => "code")
    expect(payload.fetch("proprietor")).to include(
      "id" => proprietor.id,
      "code" => "PROP-9044",
      "name" => "Thiago Proprietário",
      "phone" => "5521990872427",
      "cpf_cnpj" => "123.456.789-00",
      "email" => "thiago@example.com",
      "city" => "Itajaí"
    )
  end

  it "exporta planilha de captações para perfil administrativo" do
    manager_profile, administrative_profile = default_administrative_profiles
    administrative = create(:admin_user, profile: manager_profile, horizontal_profile: administrative_profile, name: "Iasmim")
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: administrative,
      codigo: "8571",
      nome_empreendimento: "Calls",
      unidade_numero: "101",
      proprietario: "Tarrassa",
      proprietario_celular: "47992485780",
      proprietario_email: "proprietario@example.com",
      categoria: "Apartamento",
      intake_modalidade: "venda",
      status: "Venda",
      regiao_foco: "Sim",
      valor_venda_cents: 17_000_000_00,
      valor_locacao_cents: 0,
      salute_rental_management_answer: "nao",
      foto_classificacao: "Não tem fotos/ruins",
      exibir_no_site_flag: false
    )
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Central",
      numero: "100",
      complemento: "Casa 12",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    sign_in administrative

    expect {
      get export_admin_captacoes_path
    }.to change(DataExportAuditLog, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("captacoes_")

    rows = CSV.parse(response.body, headers: true, col_sep: ";")
    expect(rows.headers).to include("Data", "Responsável Cadastro", "Empreendimento", "Cód. Imóvel CRM", "Status")
    expect(rows.first["Responsável Cadastro"]).to eq("Iasmim")
    expect(rows.first["Empreendimento"]).to eq("Calls")
    expect(rows.first["Nº Imóvel"]).to eq("101")
    expect(rows.first["Cód. Imóvel CRM"]).to eq("8571")
    expect(rows.first["nome_proprietario"]).to eq("Tarrassa")
    expect(rows.first["Cidade"]).to eq("Balneário Camboriú")
    expect(rows.first["Time"]).to eq("Time Venda")
    expect(rows.first["Valor de venda"]).to eq("R$ 17.000.000,00")
    expect(rows.first["Administração"]).to eq("NÃO")
    expect(rows.first["Status"]).to eq("Não foi publicado - Não tem fotos/ruins")

    log = DataExportAuditLog.last
    expect(log).to have_attributes(resource_name: "captacoes", export_type: "csv_export", record_count: 1)
  end

  it "bloqueia exportação de captações para corretor" do
    broker_profile = default_agent_profile
    broker = create(:admin_user, profile: broker_profile)
    sign_in broker

    expect {
      get export_admin_captacoes_path
    }.not_to change(DataExportAuditLog, :count)

    expect(response).to redirect_to(admin_captacoes_path)
  end

  it "cria rascunho somente quando o corretor inicia a captação" do
    expect {
      post admin_captacoes_path, params: {
        habitation: {
          cadastro_type: "terrenos",
          categoria: "Terreno em Condomínio",
          modalidade: "locacao_anual"
        }
      }
    }.to change { Habitation.broker_intakes.count }.by(1)

    intake = Habitation.broker_intakes.order(:created_at).last
    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "proprietario"))
    expect(intake).to have_attributes(
      intake_status: "draft",
      intake_step: "proprietario",
      exibir_no_site_flag: false,
      admin_user_id: admin.id,
      categoria: "Terreno em Condomínio",
      status: "Aluguel",
      intake_modalidade: "locacao_anual"
    )
  end

  it "mantém compatibilidade com property_kind antigo ao iniciar captação" do
    post admin_captacoes_path, params: {
      habitation: {
        property_kind: "sala_comercial",
        modalidade: "venda"
      }
    }

    intake = Habitation.broker_intakes.order(:created_at).last
    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "proprietario"))
    expect(intake).to have_attributes(categoria: "Sala Comercial", status: "Venda")
  end

  it "mantém residencial legado como casa, não apartamento" do
    post admin_captacoes_path, params: {
      habitation: {
        property_kind: "residencial",
        modalidade: "locacao_anual"
      }
    }

    intake = Habitation.broker_intakes.order(:created_at).last
    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "proprietario"))
    expect(intake).to have_attributes(categoria: "Casa", status: "Aluguel")
    expect(intake).not_to be_requires_unit_number
  end

  it "envia sala comercial para revisão usando salas como dimensão física" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      categoria: "Sala Comercial",
      titulo_anuncio: "Sala Comercial em Centro Balneário Camboriú",
      descricao_web: "Descrição pública da sala comercial para publicação.",
      dormitorios_qtd: 0,
      suites_qtd: 0,
      vagas_qtd: 0,
      salas_qtd: 0
    )
    intake.create_address!(
      cep: "88330-001",
      logradouro: "Avenida Brasil",
      numero: "577",
      complemento: "Sala 402",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    intake.autorizacoes_venda.attach(
      io: StringIO.new("autorizacao"),
      filename: "autorizacao.txt",
      content_type: "text/plain"
    )

    post submit_for_review_admin_captacao_path(intake), params: {
      habitation: {
        salas: "1"
      }
    }

    expect(response).to redirect_to(admin_captacao_path(intake))
    expect(intake.reload).to have_attributes(
      intake_status: "submitted_for_admin_review",
      salas_qtd: 1
    )
  end

  it "salva campos auxiliares do wizard de captação em habitation" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "infraestrutura")

    patch admin_captacao_path(intake), params: {
      current_step: "proprietario",
      direction: "forward",
      captacao: {
        proprietario_cidade: "Itajaí"
      }
    }

    intake.reload
    expect(intake.proprietario_cidade).to eq("Itajaí")

    intake.update_column(:intake_step, "caracteristicas")
    patch admin_captacao_path(intake), params: {
      current_step: "caracteristicas",
      direction: "forward",
      captacao: {
        area_total: "120",
        area_privativa: "100",
        dormitorios: "2",
        banheiros: "1",
        sacada: "1",
        terraco: "0",
        dependencia_empregada: "1",
        precisa_reforma: "0"
      }
    }

    intake.reload
    expect(intake.sacada).to eq(true)
    expect(intake.dependencia_empregada).to eq(true)
    expect(intake.terraco).to eq(false)
    expect(intake.precisa_reforma).to eq(false)
    expect(intake.caracteristicas).to include("Sacada", "Dependência de empregada")

    patch admin_captacao_path(intake), params: {
      current_step: "infraestrutura",
      direction: "forward",
      captacao: {
        distancia_praia: "350",
        caracteristicas_predio: ["Elevador"]
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "negociacao"))
    intake.reload
    expect(intake.infra_estrutura).to include("Elevador")
    expect(intake.distancia_praia).to eq("350")
    expect(intake.observacoes_visitas).to include("Distância da praia: 350 m")
    intake.update_column(:intake_step, "visitas")

    patch admin_captacao_path(intake), params: {
      current_step: "visitas",
      direction: "forward",
      captacao: {
        chaves_com: "proprietario",
        dias_visitas: ["Seg", "Tarde"],
        senha_imovel: "1234",
        senha_portaria: "5678",
        observacoes: "Observação livre"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "fotos"))
    intake.reload
    expect(intake.key_location).to eq("Proprietário")
    expect(intake.chaves_com).to eq("proprietario")
    expect(intake.dias_visitas).to eq(["Seg", "Tarde"])
    expect(intake.senha_imovel).to eq("1234")
    expect(intake.senha_portaria).to eq("5678")
    expect(intake.observacoes).to eq("Observação livre")
  end

  it "renderiza todas as opções e campos dinâmicos de localização das chaves" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "visitas", codigo: "KEY-OPTIONS-#{SecureRandom.hex(6)}")

    get edit_admin_captacao_path(intake, step: "visitas")

    expect(response).to have_http_status(:ok)
    Habitation::CAPTACAO_KEY_LOCATION_OPTIONS.each do |value, label|
      expect(response.body).to include(%(value="#{value}"))
      expect(response.body).to include(label)
    end
    expect(response.body).to include("Onde estão as chaves?")
    expect(response.body).to include("Nome do zelador")
    expect(response.body).to include('data-conditional-reveal-values="portaria"')
  end

  it "salva extras de terreno do wizard em campos estruturados" do
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Terreno", intake_step: "caracteristicas")

    patch admin_captacao_path(intake), params: {
      current_step: "caracteristicas",
      direction: "forward",
      captacao: {
        area_total: "360",
        caracteristicas_imovel: ["Murado"],
        extras: {
          frente_metros: "12",
          topografia: "plano",
          face: "Norte"
        }
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "infraestrutura"))
    intake.reload
    expect(intake.dimensoes_terreno).to include("Frente: 12 m")
    expect(intake.topografia).to eq("Plano")
    expect(intake.face).to eq("Norte")
    expect(intake.extras).to include(
      "frente_metros" => "12",
      "topografia" => "plano",
      "face" => "Norte"
    )
  end

  it "bloqueia envio para revisão quando faltam campos obrigatórios" do
    intake = create(:habitation, :broker_intake, admin_user: admin, proprietario: nil)

    post submit_for_review_admin_captacao_path(intake)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(intake.reload.intake_status).to eq("draft")
  end

  it "renderiza a etapa de fotos com lista ordenável e agendamento reativo" do
    GoogleCalendarIntegrationSetting.for(Tenant.default).update!(
      enabled: true,
      calendar_id: "fotografias.saluteimoveis@gmail.com",
      default_duration_minutes: 60,
      service_account_json: {
        type: "service_account",
        client_email: "calendar-sync@example.com",
        private_key: "-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----\n"
      }.to_json
    )
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "fotos")

    get edit_admin_captacao_path(intake, step: "fotos")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-controller=\"captacao-photos\"")
    expect(response.body).to include("captacao-submit-progress")
    expect(response.body).to include("Fotos selecionadas agora")
    expect(response.body).to include("Adicionar fotos")
    expect(response.body).to include("Agendar fotógrafo")
    expect(response.body).not_to include("Agendar no Google Agenda")
    expect(response.body).to include("Você pode adicionar mais antes de avançar.")
    expect(response.body).to include("Escolher horário")
    expect(response.body).not_to include("Abrir agenda de fotos")
  end

  it "bloqueia avanço no próprio step e marca campos obrigatórios" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "endereco")

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      direction: "forward",
      habitation: {
        zip_code: "",
        street: "",
        street_number: "",
        neighborhood: "",
        city: "",
        state: "",
        edificio_nome: ""
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe o CEP.")
    expect(response.body).to include("is-invalid")
    expect(intake.reload.intake_step).to eq("endereco")
  end

  it "exige cidade do proprietário no passo de proprietário" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "proprietario")

    patch admin_captacao_path(intake), params: {
      current_step: "proprietario",
      direction: "forward",
      habitation: {
        proprietario_nome: "Mário",
        proprietario_telefone: "(47) 99999-0000",
        proprietario_cidade: ""
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe a cidade do proprietário.")
    expect(intake.reload.intake_step).to eq("proprietario")
  end

  it "marca quantidades obrigatórias zeradas no step de características" do
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Apartamento", intake_step: "caracteristicas")

    patch admin_captacao_path(intake), params: {
      current_step: "caracteristicas",
      direction: "forward",
      habitation: {
        area_total: "228",
        area_privativa: "0",
        dormitorios: "0",
        banheiros: "0",
        caracteristicas_imovel: [],
        caracteristicas_predio: []
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe a área privativa do imóvel.")
    expect(response.body).to include("Informe a quantidade de dormitórios.")
    expect(response.body).to include("Informe a quantidade de banheiros.")
    expect(response.body).to include("is-invalid")
    expect(intake.reload.intake_step).to eq("caracteristicas")
  end

  it "exige área privativa para casa de rua mesmo com área total preenchida" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      categoria: "Casa",
      intake_step: "caracteristicas",
      area_privativa_m2: nil,
      area_total_m2: nil
    )

    patch admin_captacao_path(intake), params: {
      current_step: "caracteristicas",
      direction: "forward",
      habitation: {
        area_total: "228",
        area_privativa: "",
        dormitorios: "3",
        banheiros: "4",
        caracteristicas_imovel: ["Piscina"]
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe a área privativa do imóvel.")
    expect(response.body).to include("is-invalid")
    expect(intake.reload.intake_step).to eq("caracteristicas")
  end

  it "aceita área privativa para casa de rua sem exigir área total" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      categoria: "Casa",
      intake_step: "caracteristicas",
      area_privativa_m2: nil,
      area_total_m2: nil
    )

    patch admin_captacao_path(intake), params: {
      current_step: "caracteristicas",
      direction: "forward",
      habitation: {
        area_total: "",
        area_privativa: "120",
        dormitorios: "3",
        banheiros: "4",
        caracteristicas_imovel: ["Piscina"]
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "infraestrutura"))
    intake.reload
    expect(intake.area_privativa_m2.to_i).to eq(120)
    expect(intake.area_total_m2.to_f).to eq(0)
  end

  it "carrega características do catálogo do cadastro completo na captação" do
    AttributeOption.create!(context: "habitation", category: "feature", name: "Vista panorâmica")
    AttributeOption.create!(context: "habitation", category: "infrastructure", name: "Espaço gourmet")
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Apartamento", intake_step: "caracteristicas")

    get edit_admin_captacao_path(intake, step: "caracteristicas")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Vista panorâmica")

    get edit_admin_captacao_path(intake, step: "infraestrutura")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Espaço gourmet")
  end

  it "separa características do imóvel e do edifício em etapas diferentes" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "caracteristicas")

    patch admin_captacao_path(intake), params: {
      current_step: "caracteristicas",
      direction: "forward",
      habitation: {
        area_total: "120",
        area_privativa: "100",
        dormitorios: "2",
        banheiros: "2",
        caracteristicas_imovel: ["Sacada"]
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "infraestrutura"))
  end

  it "limpa opções técnicas e duplicadas na ficha de captação" do
    now = Time.current
    AttributeOption.insert_all([
      { tenant_id: admin.tenant_id, context: "habitation", category: "feature", name: "ar_condicionado", created_at: now, updated_at: now },
      { tenant_id: admin.tenant_id, context: "habitation", category: "feature", name: "Ar Condicionado", created_at: now, updated_at: now },
      { tenant_id: admin.tenant_id, context: "habitation", category: "feature", name: "banheiro_social", created_at: now, updated_at: now }
    ])
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "caracteristicas")

    get edit_admin_captacao_path(intake, step: "caracteristicas")

    expect(response).to have_http_status(:ok)
    expect(response.body.scan('value="Ar-condicionado"').size).to eq(1)
    expect(response.body).to include("Banheiro social")
    expect(response.body).not_to include("ar_condicionado")
    expect(response.body).not_to include("banheiro_social")
  end

  it "vincula empreendimento por busca e mantém o nome na ficha PWA" do
    development = create(
      :habitation,
      codigo: "DEV-PWA-#{SecureRandom.hex(4)}",
      tipo: "Empreendimento",
      categoria: "Empreendimento",
      nome_empreendimento: "Residencial PWA Busca"
    )
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      categoria: "Apartamento",
      intake_step: "endereco",
      nome_empreendimento: nil,
      codigo_empreendimento: nil
    )

    get edit_admin_captacao_path(intake, step: "endereco")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Empreendimento cadastrado")
    expect(response.body).to include("Residencial PWA Busca")

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      direction: "forward",
      habitation: {
        zip_code: "88330-030",
        street: "Rua 1500",
        street_number: "123",
        neighborhood: "Centro",
        city: "Balneário Camboriú",
        state: "SC",
        codigo_empreendimento: development.codigo,
        unidade_numero: "1201"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "caracteristicas"))
    intake.reload
    expect(intake.codigo_empreendimento).to eq(development.codigo)
    expect(intake.nome_empreendimento).to eq("Residencial PWA Busca")

    get edit_admin_captacao_path(intake, step: "endereco")

    expect(response.body).to include("Residencial PWA Busca")
  end

  it "aceita valores monetários formatados na negociação" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "negociacao")

    patch admin_captacao_path(intake), params: {
      current_step: "negociacao",
      direction: "forward",
      habitation: {
        valor_venda: "1.234.567,89",
        valor_condominio: "1.000,00",
        valor_iptu: "500,00",
        saldo_devedor: "120.000,00",
        aceita_permuta_answer: "nao",
        aceita_parcelamento_flag: "false"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "visitas"))
    expect(intake.reload.valor_venda_cents).to eq(123_456_789)
    expect(intake.valor_condominio_cents).to eq(100_000)
    expect(intake.valor_iptu_cents).to eq(50_000)
    expect(intake.saldo_devedor_cents).to eq(12_000_000)
  end

  it "mantém venda e locação como modalidade única durante o rascunho" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "negociacao", intake_modalidade: "ambos")

    get edit_admin_captacao_path(intake, step: "negociacao")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Valor de venda")
    expect(response.body).to include("Valor de locação")
  end

  it "mantém rascunho incompleto sem valor, mas bloqueia envio para revisão" do
    intake = create(:habitation, :broker_intake, admin_user: admin, valor_venda_cents: nil)

    post submit_for_review_admin_captacao_path(intake)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe um valor de venda válido")
    expect(intake.reload.intake_status).to eq("draft")
  end

  it "anexa autorização enviada no passo de fotos antes de validar avanço" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "fotos", photo_flow_choice: "upload")
    intake.photos.attach(
      io: StringIO.new("foto"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )
    authorization = Rack::Test::UploadedFile.new(
      StringIO.new("autorizacao"),
      "image/png",
      original_filename: "autorizacao.png"
    )

    patch admin_captacao_path(intake), params: {
      current_step: "fotos",
      direction: "forward",
      habitation: {
        photos: [""],
        autorizacoes_venda: [authorization]
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "review"))
    expect(intake.reload.autorizacoes_venda).to be_attached
    expect(intake.photos).to be_attached
  end

  it "não remove anexos existentes quando o navegador envia campos de arquivo vazios" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "fotos", photo_flow_choice: "upload")
    intake.photos.attach(io: StringIO.new("foto"), filename: "foto.jpg", content_type: "image/jpeg")
    intake.autorizacoes_venda.attach(io: StringIO.new("autorizacao"), filename: "autorizacao.png", content_type: "image/png")

    patch admin_captacao_path(intake), params: {
      current_step: "fotos",
      direction: "forward",
      habitation: {
        photos: [""],
        autorizacoes_venda: [""]
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "review"))
    expect(intake.reload.photos).to be_attached
    expect(intake.autorizacoes_venda).to be_attached
  end

  it "bloqueia valor simbólico na negociação" do
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "negociacao")

    patch admin_captacao_path(intake), params: {
      current_step: "negociacao",
      direction: "forward",
      habitation: {
        valor_venda: "1,00",
        valor_condominio: "1.000,00",
        valor_iptu: "500,00",
        aceita_permuta_answer: "nao",
        aceita_parcelamento_flag: "false"
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("mínimo R$ 10.000")
    expect(response.body).to include("is-invalid")
    expect(intake.reload.intake_step).to eq("negociacao")
  end

  it "bloqueia avanço da captação quando endereço completo já existe" do
    existing = create(:habitation, nome_empreendimento: "Residencial Atlântico", bloco: "301")
    existing.create_address!(
      logradouro: "Rua 3000",
      numero: "50",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    intake = create(:habitation, :broker_intake, admin_user: admin, intake_step: "endereco")

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      direction: "forward",
      habitation: {
        street: "Rua 3000",
        zip_code: "88330-000",
        street_number: "50",
        neighborhood: "Centro",
        city: "Balneário Camboriú",
        state: "SC",
        edificio_nome: "Residencial Atlantico",
        unidade_numero: "ap 301"
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Já existe imóvel cadastrado")
    expect(intake.reload.intake_step).to eq("endereco")
  end

  it "não bloqueia apartamento com unidade quando existe cadastro do empreendimento no mesmo endereço" do
    development = create(:habitation, categoria: "Apartamento", nome_empreendimento: "Residencial Atlântico", bloco: nil, complemento: nil)
    development.create_address!(
      logradouro: "Rua 3000",
      numero: "50",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Apartamento", intake_step: "endereco")

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      direction: "forward",
      habitation: {
        zip_code: "88330-000",
        street: "Rua 3000",
        street_number: "50",
        neighborhood: "Centro",
        city: "Balneário Camboriú",
        state: "SC",
        edificio_nome: "Residencial Atlantico",
        unidade_numero: "ap 302"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "caracteristicas"))
    expect(intake.reload.bloco).to eq("ap 302")
  end

  it "trata casa de rua como casa quando o campo de edifício veio como Casa sem unidade" do
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Apartamento", intake_step: "endereco")

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      direction: "forward",
      habitation: {
        zip_code: "88330-422",
        street: "Rua 2350",
        street_number: "490",
        neighborhood: "Centro",
        city: "Balneário Camboriú",
        state: "SC",
        edificio_nome: "Casa",
        unidade_numero: ""
      }
    }

    intake.reload
    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "caracteristicas"))
    expect(intake.categoria).to eq("Casa")
    expect(intake).not_to be_requires_unit_number
  end

  it "não exige dados de edifício para sala comercial de rua" do
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Sala Comercial", intake_step: "infraestrutura", infra_estrutura: [])

    patch admin_captacao_path(intake), params: {
      current_step: "infraestrutura",
      direction: "forward",
      habitation: {
        distancia_praia: "250"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "negociacao"))
    expect(intake.reload.distancia_praia).to eq("250")
  end

  it "não exige infraestrutura de edifício para casa ou galpão" do
    ["Casa", "Galpão"].each do |categoria|
      intake = create(:habitation, :broker_intake, admin_user: admin, categoria: categoria, intake_step: "infraestrutura", infra_estrutura: [])

      patch admin_captacao_path(intake), params: {
        current_step: "infraestrutura",
        direction: "forward",
        habitation: {
          distancia_praia: "100"
        }
      }

      expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "negociacao"))
      expect(intake.reload.distancia_praia).to eq("100")
    end
  end

  it "exige empreendimento para casa em condomínio sem exigir unidade" do
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Casa em Condomínio", nome_empreendimento: nil, bloco: nil, intake_step: "endereco")

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      direction: "forward",
      habitation: {
        zip_code: "88330-000",
        street: "Rua 3000",
        street_number: "50",
        neighborhood: "Centro",
        city: "Balneário Camboriú",
        state: "SC",
        edificio_nome: "",
        unidade_numero: ""
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe o empreendimento/condomínio.")
    expect(response.body).to include("Informe o complemento.")
    expect(response.body).not_to include("Informe o número da unidade.")
  end

  it "salva complemento obrigatório para casa em condomínio" do
    intake = create(:habitation, :broker_intake, admin_user: admin, categoria: "Casa em Condomínio", nome_empreendimento: nil, bloco: nil, intake_step: "endereco")

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      direction: "forward",
      habitation: {
        zip_code: "88330-000",
        street: "Rua 3001",
        street_number: "51",
        neighborhood: "Centro",
        city: "Balneário Camboriú",
        state: "SC",
        edificio_nome: "Condomínio Atlântico",
        complemento: "Casa 12"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "caracteristicas"))
    intake.reload
    expect(intake.nome_empreendimento).to eq("Condomínio Atlântico")
    expect(intake.complemento).to eq("Casa 12")
  end

  it "exige ocupação, situação, chaves e dias de visita na captação" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      intake_step: "caracteristicas",
      ocupacao_status: nil,
      situacao: nil,
      key_location: nil,
      observacoes_visitas: "Cidade do proprietário: Balneário Camboriú"
    )

    patch admin_captacao_path(intake), params: {
      current_step: "caracteristicas",
      direction: "forward",
      habitation: {
        area_privativa: "80",
        dormitorios: "2",
        banheiros: "1",
        vagas_garagem: "1",
        caracteristicas_imovel: ["Sacada"]
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe a ocupação do imóvel.")
    expect(response.body).to include("Informe a situação do imóvel.")

    intake.update!(ocupacao_status: "Desocupado", situacao: "Usado", intake_step: "visitas")
    patch admin_captacao_path(intake), params: {
      current_step: "visitas",
      direction: "forward",
      habitation: {
        chaves_com: "",
        dias_visitas: []
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe onde estão as chaves.")
    expect(response.body).to include("Informe os melhores dias/horários para visita.")
  end

  it "exige meio de garantia locatícia para captação de aluguel" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      status: "Aluguel",
      intake_modalidade: "locacao_anual",
      valor_venda_cents: 0,
      valor_locacao_cents: 8_000_00,
      salute_rental_management_answer: "sim",
      rental_guarantee_method: nil,
      intake_step: "negociacao"
    )

    patch admin_captacao_path(intake), params: {
      current_step: "negociacao",
      direction: "forward",
      habitation: {
        valor_locacao: "8.000,00",
        valor_condominio: "500,00",
        valor_iptu: "100,00",
        salute_rental_management_answer: "sim",
        rental_guarantee_method: ""
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Informe ao menos um meio de garantia locatícia.")
  end

  it "permite selecionar mais de uma garantia locatícia na ficha PWA" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      status: "Aluguel",
      intake_modalidade: "locacao_anual",
      valor_venda_cents: 0,
      valor_locacao_cents: 8_000_00,
      valor_condominio_cents: 500_00,
      valor_iptu_cents: 100_00,
      salute_rental_management_answer: "sim",
      rental_guarantee_method: "Seguro fiança",
      intake_step: "negociacao"
    )

    get edit_admin_captacao_path(intake, step: "negociacao")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="habitation[rental_guarantee_method][]"')
    expect(response.body).to include("Meios de garantia locatícia")

    patch admin_captacao_path(intake), params: {
      current_step: "negociacao",
      direction: "forward",
      habitation: {
        valor_locacao: "8.000,00",
        valor_condominio: "500,00",
        valor_iptu: "100,00",
        salute_rental_management_answer: "sim",
        rental_guarantee_method: ["Seguro fiança", "Caução"]
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "visitas"))
    expect(intake.reload.rental_guarantee_methods).to contain_exactly("Seguro fiança", "Caução")
  end

  it "envia, aprova e libera para o site quando a ficha está completa" do
    broker_profile = default_agent_profile
    broker = create(:admin_user, profile: broker_profile)
    intake = create(:habitation, :broker_intake, admin_user: broker)
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

    sign_in broker
    post submit_for_review_admin_captacao_path(intake)
    expect(response).to redirect_to(admin_captacao_path(intake))
    expect(intake.reload.intake_status).to eq("submitted_for_admin_review")

    sign_in admin
    post approve_admin_captacao_path(intake), params: { admin_review_notes: "Ok" }
    expect(response).to redirect_to(admin_captacao_path(intake))
    expect(intake.reload.intake_status).to eq("admin_approved")

    post release_to_site_admin_captacao_path(intake)
    expect(response).to redirect_to(admin_captacao_path(intake))
    expect(flash[:alert]).to eq("Apenas o captador responsável pode publicar no site.")
    expect(intake.reload).to have_attributes(intake_status: "admin_approved", exibir_no_site_flag: false)

    sign_in broker
    post release_to_site_admin_captacao_path(intake)
    expect(response).to redirect_to(admin_captacao_path(intake))
    expect(intake.reload).to have_attributes(intake_status: "published", exibir_no_site_flag: true)
  end

  it "mostra título e descrição do anúncio para o corretor conferir antes da publicação" do
    broker_profile = default_agent_profile
    broker = create(:admin_user, profile: broker_profile)
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: broker,
      intake_status: "admin_approved",
      categoria: "Casa",
      titulo_anuncio: "Apartamento 3 dormitórios em Centro Balneário Camboriú",
      descricao_web: "Descrição pública revisada para a corretora conferir.",
      dormitorios_qtd: 3
    )
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Central",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    sign_in broker
    get admin_captacao_path(intake)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Casa 3 dormitórios em Centro Balneário Camboriú")
    expect(response.body).to include("Anúncio para publicação")
    expect(response.body).to include("Apartamento 3 dormitórios em Centro Balneário Camboriú")
    expect(response.body).to include("Incoerente com a categoria")
    expect(response.body).to include("Descrição pública revisada para a corretora conferir.")
  end

  it "lista pendências específicas quando corretor tenta publicar captação não pronta" do
    broker_profile = default_agent_profile
    broker = create(:admin_user, profile: broker_profile)
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: broker,
      intake_status: "admin_approved",
      categoria: "Casa",
      titulo_anuncio: "Apartamento 3 dormitórios em Centro Balneário Camboriú",
      descricao_web: "Descrição pública revisada.",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      dormitorios_qtd: 3
    )
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

    sign_in broker
    post release_to_site_admin_captacao_path(intake)

    expect(response).to redirect_to(admin_captacao_path(intake))
    expect(flash[:alert]).to include("Esta captação ainda não está pronta para liberar no site.")
    expect(flash[:alert]).to include("Título do anúncio coerente com a categoria")
    expect(intake.reload).to have_attributes(intake_status: "admin_approved", exibir_no_site_flag: false)
  end

  it "impede aprovação administrativa quando ainda faltam dados obrigatórios" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      intake_status: "submitted_for_admin_review",
      proprietario: nil,
      proprietario_celular: nil,
      observacoes_visitas: ""
    )

    post approve_admin_captacao_path(intake), params: { admin_review_notes: "Ok" }

    expect(response).to redirect_to(admin_captacao_path(intake))
    expect(flash[:alert]).to include("Complete os campos obrigatórios antes de aprovar")
    expect(flash[:alert]).to include("Dados do proprietário")
    expect(intake.reload.intake_status).to eq("submitted_for_admin_review")
  end

  it "bloqueia campos sensíveis para corretor após publicação no site" do
    broker_profile = default_agent_profile
    broker = create(:admin_user, profile: broker_profile)
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: broker,
      intake_status: "published",
      intake_step: "negociacao",
      exibir_no_site_flag: true,
      nome_empreendimento: "Residencial Original",
      titulo_anuncio: "Título original",
      descricao_web: "Descrição original",
      proprietario: "Proprietário original",
      proprietario_celular: "5547999990000",
      valor_venda_cents: 900_000_00
    )
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Original",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    sign_out admin
    sign_in broker

    patch admin_captacao_path(intake), params: {
      current_step: "negociacao",
      habitation: {
        edificio_nome: "Residencial Alterado",
        titulo_anuncio: "Título alterado",
        descricao_web: "Descrição alterada",
        proprietario_nome: "Proprietário alterado",
        proprietario_telefone: "(47) 98888-1111",
        zip_code: "88331-000",
        street: "Rua Alterada",
        street_number: "200",
        neighborhood: "Barra Sul",
        city: "Itajaí",
        state: "SC",
        valor_venda: "1200000"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "visitas"))
    intake.reload
    expect(intake).to have_attributes(
      nome_empreendimento: "Residencial Original",
      titulo_anuncio: "Título original",
      proprietario: "Proprietário original",
      proprietario_celular: "5547999990000",
      valor_venda_cents: 120_000_000
    )
    expect(intake.descricao_web.to_plain_text).to eq("Descrição original")
    expect(intake.address).to have_attributes(
      logradouro: "Rua Original",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      cep: "88330-000"
    )
  end

  it "permite que administrativo altere campos sensíveis após publicação" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      intake_status: "published",
      intake_step: "endereco",
      exibir_no_site_flag: true,
      nome_empreendimento: "Residencial Original",
      titulo_anuncio: "Título original",
      descricao_web: "Descrição original",
      proprietario: "Proprietário original"
    )
    intake.create_address!(
      cep: "88330-000",
      logradouro: "Rua Original",
      numero: "100",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC"
    )

    patch admin_captacao_path(intake), params: {
      current_step: "endereco",
      habitation: {
        edificio_nome: "Residencial Alterado",
        zip_code: "88331-000",
        street: "Rua Alterada",
        street_number: "200",
        complemento: "Casa 12",
        neighborhood: "Barra Sul",
        city: "Itajaí",
        state: "SC"
      }
    }

    expect(response).to redirect_to(edit_admin_captacao_path(intake, step: "caracteristicas"))
    intake.reload
    expect(intake.nome_empreendimento).to eq("Residencial Alterado")
    expect(intake.address).to have_attributes(
      logradouro: "Rua Alterada",
      numero: "200",
      bairro: "Barra Sul",
      cidade: "Itajaí",
      cep: "88331-000"
    )
  end

  it "desdobra venda e locação em dois cadastros ao enviar para revisão" do
    intake = create(
      :habitation,
      :broker_intake,
      admin_user: admin,
      intake_modalidade: "ambos",
      valor_venda_cents: 1_200_000_00,
      valor_locacao_cents: 8_500_00,
      salute_rental_management_answer: "sim"
    )
    intake.create_address!(
      cep: "88330-100",
      logradouro: "Rua Dupla",
      numero: "200",
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

    expect {
      post submit_for_review_admin_captacao_path(intake)
    }.to change { Habitation.broker_intakes.count }.by(1)

    expect(response).to redirect_to(admin_captacao_path(intake))
    sale = intake.reload
    rental = Habitation.where(intake_group_uuid: sale.intake_group_uuid).where.not(id: sale.id).sole
    expect(sale).to have_attributes(
      intake_status: "submitted_for_admin_review",
      intake_modalidade: "venda",
      status: "Venda",
      valor_venda_cents: 1_200_000_00,
      valor_locacao_cents: 0
    )
    expect(rental).to have_attributes(
      intake_status: "submitted_for_admin_review",
      intake_modalidade: "locacao_anual",
      status: "Aluguel",
      valor_venda_cents: 0,
      valor_locacao_cents: 8_500_00,
      intake_group_uuid: sale.intake_group_uuid
    )
    expect(rental.address.logradouro).to eq("Rua Dupla")
    expect(rental.autorizacoes_venda).to be_attached
  end
end
