require "rails_helper"

RSpec.describe "Admin habitation catalog filters", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "admin-#{SecureRandom.hex(8)}@salute.test") }
  let(:turbo_frame_headers) { { "Turbo-Frame" => "habitations_filter_inspector" } }

  def default_agent_profile
    admin.tenant.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
  end

  before do
    host! "localhost"
    sign_in admin
  end

  def create_catalog_property(attributes = {}, address: nil, **keyword_attributes)
    attributes = attributes.merge(keyword_attributes)
    address_attributes = attributes.extract!(
      :tipo_endereco,
      :logradouro,
      :numero,
      :bairro,
      :bairro_comercial,
      :cidade,
      :uf,
      :cep
    )
    defaults = {
      tenant: admin.tenant,
      codigo: "FLT-#{SecureRandom.hex(6)}",
      titulo_anuncio: "Filtro #{SecureRandom.hex(8)}",
      categoria: "Apartamento",
      status: "Venda",
      tipo: "Unitário",
      exibir_no_site_flag: false,
      data_cadastro_crm: Time.zone.local(2026, 1, 1),
      data_atualizacao_crm: Time.zone.local(2026, 1, 1),
      pictures: [{ "url" => "https://example.com/filter.jpg", "ordem" => 1, "principal" => true }]
    }
    default_address = {
      logradouro: "Rua 1000",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC",
      pais: "Brasil"
    }
    merged_address = default_address.merge(address_attributes).merge(address || {})

    create(:habitation, defaults.merge(attributes)).tap do |habitation|
      if habitation.address
        habitation.address.update!(merged_address)
      else
        habitation.create_address!(merged_address)
      end
    end
  end

  def high_catalog_code(prefix_digit = 9)
    return "#{prefix_digit}#{SecureRandom.random_number(10**11).to_s.rjust(11, '0')}" unless prefix_digit.to_i == 9

    @high_catalog_code_sequence = @high_catalog_code_sequence.to_i + 1
    "922337203685400#{@high_catalog_code_sequence.to_s.rjust(4, '0')}"
  end

  def expect_catalog_filter(label, params, matching_attrs:, nonmatching_attrs:, matching_address: nil, nonmatching_address: nil)
    matching_title = matching_attrs[:titulo_anuncio] || "Filtro #{label} match #{SecureRandom.hex(6)}"
    nonmatching_title = nonmatching_attrs[:titulo_anuncio] || "Filtro #{label} miss #{SecureRandom.hex(6)}"
    matching_code = matching_attrs[:codigo] || high_catalog_code(9)
    nonmatching_code = nonmatching_attrs[:codigo] || high_catalog_code(8)
    create_catalog_property({ codigo: matching_code, titulo_anuncio: matching_title }.merge(matching_attrs), address: matching_address)
    create_catalog_property({ codigo: nonmatching_code, titulo_anuncio: nonmatching_title }.merge(nonmatching_attrs), address: nonmatching_address)

    get admin_habitations_path(params)

    expect(response).to have_http_status(:ok)
    expect(response.body.include?(matching_code)).to eq(true), catalog_filter_failure_message(label, matching_code, nonmatching_code)
    expect(response.body.include?(nonmatching_code)).to eq(false), "filtro #{label} deixou passar imóvel incompatível #{nonmatching_code}"
  end

  def catalog_filter_failure_message(label, matching_code, nonmatching_code)
    document = Nokogiri::HTML(response.body)
    summary = document.at_css(".habitations-workspace-heading__meta")&.text&.squish
    empty = document.at_css(".ax-property-empty")&.text&.squish
    rendered_refs = response.body.scan(%r{REF:?\s*<strong>([^<]+)</strong>}).flatten
    "esperava encontrar imóvel #{matching_code} para filtro #{label}; " \
      "nao encontrou. nonmatching_present=#{response.body.include?(nonmatching_code)} " \
      "summary=#{summary.inspect} empty=#{empty.inspect} refs=#{rendered_refs.first(10).inspect}"
  end

  it "mantém compatibilidade do filtro legado exibir_no_site_portal usando a flag genérica do site" do
    matching_code = high_catalog_code(9)
    nonmatching_code = high_catalog_code(8)
    create_catalog_property(codigo: matching_code, titulo_anuncio: "Filtro legado site match #{SecureRandom.hex(6)}", exibir_no_site_flag: true)
    create_catalog_property(codigo: nonmatching_code, titulo_anuncio: "Filtro legado site miss #{SecureRandom.hex(6)}", exibir_no_site_flag: false)

    get admin_habitations_path(exibir_no_site_portal: "1")

    expect(response).to have_http_status(:ok)
    expect(response.body.include?(matching_code)).to eq(true), catalog_filter_failure_message("exibir_no_site_portal", matching_code, nonmatching_code)
    expect(response.body.include?(nonmatching_code)).to eq(false)
  end

  it "aplica os novos filtros rápidos do catálogo" do
    expect_catalog_filter(
      "semi_mobiliado",
      { scope: "semi_mobiliado" },
      matching_attrs: { caracteristicas: { "Semi mobiliado" => "Semi mobiliado" } },
      nonmatching_attrs: { mobiliado_flag: true, caracteristicas: ["Mobiliado"] }
    )
    expect_catalog_filter(
      "sem_mobilia",
      { scope: "sem_mobilia" },
      matching_attrs: { sem_mobilia_flag: true },
      nonmatching_attrs: { sem_mobilia_flag: false }
    )
    expect_catalog_filter(
      "diferenciado",
      { scope: "diferenciado" },
      matching_attrs: { categoria: "Diferenciado" },
      nonmatching_attrs: { categoria: "Apartamento" }
    )
    expect_catalog_filter(
      "quadra_mar",
      { scope: "quadra_mar" },
      matching_attrs: { quadra_mar_flag: true },
      nonmatching_attrs: { quadra_mar_flag: false }
    )
  end

  it "renderiza campos de preço com teclado numérico e máscara BR no inspector" do
    get filter_inspector_admin_habitations_path(min_price: "800000", max_price: "1200000"),
        headers: turbo_frame_headers

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    min_price = document.at_css('input[name="min_price"]')
    max_price = document.at_css('input[name="max_price"]')
    form = document.at_css("form.habitations-inspector__form")
    close_button = document.at_css('.habitations-inspector__header button[aria-label="Recolher filtros do catálogo"]')
    clear_link = document.at_css('.habitations-inspector__actions a.ax-btn')

    expect(form["data-action"].to_s).to include("submit->ax-aside#collapseOnMobile")
    expect(close_button.at_css("i")["class"]).to include("bi-x-lg")
    expect(clear_link["href"]).to eq(admin_habitations_path(ownership: "all", clear_filters: "1"))
    expect(clear_link["data-action"].to_s).not_to include("ax-aside#collapse")

    [min_price, max_price].each do |input|
      expect(input["inputmode"]).to eq("numeric")
      expect(input["pattern"]).to eq("[0-9.]*")
      expect(input["data-controller"]).to include("currency-mask")
      expect(input["data-action"]).to include("input->currency-mask#format")
    end
  end

  it "aplica todos os filtros principais do inspector do catálogo" do
    broker = create(:admin_user, name: "Corretor Filtro")
    create_catalog_property(codigo: "EMP-900", tipo: "Empreendimento", categoria: "Empreendimento", nome_empreendimento: "Empreendimento 900")
    create_catalog_property(codigo: "EMP-100", tipo: "Empreendimento", categoria: "Empreendimento", nome_empreendimento: "Empreendimento 100")

    scalar_filter_cases = [
      ["codigo", { codigo: "COD-UNICO" }, { codigo: "COD-UNICO" }, { codigo: "COD-UNICO-#{SecureRandom.hex(3)}" }],
      ["q", { q: "Vista Alpha" }, { titulo_anuncio: "Filtro q match Vista Alpha #{SecureRandom.hex(6)}" }, { titulo_anuncio: "Filtro q miss Beta #{SecureRandom.hex(6)}" }],
      ["status", { status: "Aluguel" }, { status: "Aluguel", valor_locacao_cents: 450_000 }, { status: "Venda" }],
      ["categoria", { categoria: "Terreno" }, { categoria: "Terreno" }, { categoria: "Apartamento" }],
      ["bairro_comercial", { bairro_comercial: "Meia Praia" }, { bairro_comercial: "Meia Praia" }, { bairro_comercial: "Centro" }],
      ["situacao", { situacao: "Novo" }, { situacao: "Novo" }, { situacao: "Usado" }],
      ["promotion_status", { promotion_status: "with_promo" }, { status: "Aluguel", valor_locacao_cents: 8_000_00, valor_locacao_anterior_cents: 10_000_00 }, { status: "Aluguel", valor_locacao_cents: 8_000_00, valor_locacao_anterior_cents: nil }],
      ["accepts_exchange", { accepts_exchange: "1" }, { aceita_permuta_flag: true }, { aceita_permuta_flag: false }],
      ["accepts_installments", { accepts_installments: "1" }, { aceita_parcelamento_flag: true }, { aceita_parcelamento_flag: false }],
      ["key_location", { key_location: "Portaria" }, { key_location: "Portaria" }, { key_location: "Zelador" }],
      ["rental_management", { rental_management: "1" }, { rental_management_flag: true }, { rental_management_flag: false }],
      ["regiao_foco", { regiao_foco: "Sim" }, { regiao_foco: "Centro" }, { regiao_foco: "Não" }],
      ["dorms_min", { dorms_min: "3" }, { dormitorios_qtd: 4 }, { dormitorios_qtd: 2 }],
      ["dorms_max", { dorms_max: "2" }, { dormitorios_qtd: 2 }, { dormitorios_qtd: 4 }],
      ["suites_min", { suites_min: "2" }, { suites_qtd: 2 }, { suites_qtd: 1 }],
      ["suites_max", { suites_max: "1" }, { suites_qtd: 1 }, { suites_qtd: 2 }],
      ["banheiros_min", { banheiros_min: "3" }, { banheiros_qtd: 3 }, { banheiros_qtd: 1 }],
      ["banheiros_max", { banheiros_max: "1" }, { banheiros_qtd: 1 }, { banheiros_qtd: 3 }],
      ["vagas_min", { vagas_min: "3" }, { vagas_qtd: 3 }, { vagas_qtd: 1 }],
      ["vagas_max", { vagas_max: "1" }, { vagas_qtd: 1 }, { vagas_qtd: 3 }],
      ["area_total_min", { area_total_min: "180" }, { area_total_m2: 200 }, { area_total_m2: 120 }],
      ["area_total_max", { area_total_max: "150" }, { area_total_m2: 120 }, { area_total_m2: 220 }],
      ["area_privativa_min", { area_privativa_min: "90" }, { area_privativa_m2: 100 }, { area_privativa_m2: 70 }],
      ["area_privativa_max", { area_privativa_max: "80" }, { area_privativa_m2: 70 }, { area_privativa_m2: 120 }],
      ["destaque_web", { destaque_web: "1" }, { destaque_web_flag: true }, { destaque_web_flag: false }],
      ["festival", { festival: "1" }, { festival_flag: true }, { festival_flag: false }],
      ["exibir_no_site_portal", { exibir_no_site_portal: "1" }, { exibir_no_site_flag: true }, { exibir_no_site_flag: false }],
      ["tem_placa", { tem_placa: "1" }, { tem_placa_flag: true }, { tem_placa_flag: false }],
      ["exclusivo", { exclusivo: "1" }, { exclusivo_flag: true }, { exclusivo_flag: false }],
      ["somente_com_imagens", { somente_com_imagens: "1" }, { pictures: [{ "url" => "https://example.com/with.jpg" }] }, { pictures: [] }],
      ["somente_sem_imagens", { somente_sem_imagens: "1" }, { pictures: [] }, { pictures: [{ "url" => "https://example.com/with.jpg" }] }],
      ["somente_dwv", { somente_dwv: "1" }, { imovel_dwv: "Sim" }, { imovel_dwv: "Não" }],
      ["foto_classificacao", { foto_classificacao: ["Profissionais"] }, { foto_classificacao: "Profissionais" }, { foto_classificacao: "Aceitáveis" }],
      ["amenities", { amenities: ["Sacada"] }, { caracteristicas: ["Sacada"] }, { caracteristicas: ["Lavabo"] }],
      ["amenities_semi_mobiliado", { amenities: ["Semi mobiliado"] }, { caracteristicas: { "Semi mobiliado" => "Semi mobiliado" } }, { mobiliado_flag: true, caracteristicas: ["Mobiliado"] }],
      ["publicar_imovelweb_2", { publicar_imovelweb_2: "1" }, { publicar_imovelweb_2: true }, { publicar_imovelweb_2: false }],
      ["publicar_lais_ai", { publicar_lais_ai: "1" }, { publicar_lais_ai: true }, { publicar_lais_ai: false }],
      ["publicar_chaves_na_mao", { publicar_chaves_na_mao: "1" }, { publicar_chaves_na_mao: true }, { publicar_chaves_na_mao: false }],
      ["publicar_casa_mineira", { publicar_casa_mineira: "1" }, { publicar_casa_mineira: true }, { publicar_casa_mineira: false }],
      ["publicar_imovelweb", { publicar_imovelweb: "1" }, { publicar_imovelweb: true }, { publicar_imovelweb: false }],
      ["publicar_viva_real_vrsync", { publicar_viva_real_vrsync: "1" }, { publicar_viva_real_vrsync: true }, { publicar_viva_real_vrsync: false }],
      ["permuta_vehicle", { permuta_vehicle: "1" }, { aceita_permuta_veiculo_flag: true }, { aceita_permuta_veiculo_flag: false }],
      ["permuta_property", { permuta_property: "1" }, { aceita_permuta_imovel_flag: true }, { aceita_permuta_imovel_flag: false }],
      ["permuta_others", { permuta_others: "1" }, { aceita_permuta_outros_flag: true }, { aceita_permuta_outros_flag: false }],
      ["captacao_inicio", { captacao_inicio: "2026-06-10" }, { data_cadastro_crm: Time.zone.local(2026, 6, 20) }, { data_cadastro_crm: Time.zone.local(2026, 6, 1) }],
      ["captacao_fim", { captacao_fim: "2026-06-10" }, { data_cadastro_crm: Time.zone.local(2026, 6, 9) }, { data_cadastro_crm: Time.zone.local(2026, 6, 12) }],
      ["atualizacao_inicio", { atualizacao_inicio: "2026-06-10" }, { data_atualizacao_crm: Time.zone.local(2026, 6, 20) }, { data_atualizacao_crm: Time.zone.local(2026, 6, 1) }],
      ["atualizacao_fim", { atualizacao_fim: "2026-06-10" }, { data_atualizacao_crm: Time.zone.local(2026, 6, 9) }, { data_atualizacao_crm: Time.zone.local(2026, 6, 12) }],
      ["min_price", { min_price: "800000" }, { valor_venda_cents: 900_000_00 }, { valor_venda_cents: 700_000_00, valor_locacao_cents: 0 }],
      ["max_price", { max_price: "800000" }, { valor_venda_cents: 700_000_00 }, { valor_venda_cents: 900_000_00, valor_locacao_cents: 0 }],
      ["empreendimento_codigo", { empreendimento_codigo: "Residencial Filtro" }, { nome_empreendimento: "Residencial Filtro" }, { nome_empreendimento: "Residencial Outro" }]
    ]

    scalar_filter_cases.each do |label, params, matching_attrs, nonmatching_attrs|
      expect_catalog_filter(label, params, matching_attrs:, nonmatching_attrs:)
    end

    expect_catalog_filter(
      "corretor_id",
      { corretor_id: broker.id },
      matching_attrs: { admin_user_id: broker.id },
      nonmatching_attrs: { admin_user_id: admin.id }
    )
  end

  it "aceita múltiplas cidades no filtro de localização do catálogo" do
    bc = create_catalog_property(codigo: high_catalog_code(9), titulo_anuncio: "Filtro cidade Balneário", address: { cidade: "Balneário Camboriú" })
    itapema = create_catalog_property(codigo: high_catalog_code(9), titulo_anuncio: "Filtro cidade Itapema", address: { cidade: "Itapema" })
    outside = create_catalog_property(codigo: high_catalog_code(8), titulo_anuncio: "Filtro cidade fora", address: { cidade: "Joinville" })

    get admin_habitations_path(cidade: ["Balneário Camboriú", "Itapema"])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(bc.titulo_anuncio)
    expect(response.body).to include(itapema.titulo_anuncio)
    expect(response.body).not_to include(outside.titulo_anuncio)
    expect(response.body).to include("Cidade: Balneário Camboriú, Itapema")
  end

  it "aceita aliases do componente mobile para múltiplas categorias e cidades" do
    apartment = create_catalog_property(codigo: high_catalog_code(9), titulo_anuncio: "Alias apartamento BC", categoria: "Apartamento", address: { cidade: "Balneário Camboriú" })
    house = create_catalog_property(codigo: high_catalog_code(9), titulo_anuncio: "Alias casa Itapema", categoria: "Casa", address: { cidade: "Itapema" })
    outside = create_catalog_property(codigo: high_catalog_code(8), titulo_anuncio: "Alias terreno Joinville", categoria: "Terreno", address: { cidade: "Joinville" })

    get admin_habitations_path(category: %w[Apartamento Casa], city: ["Balneário Camboriú", "Itapema"])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(apartment.titulo_anuncio)
    expect(response.body).to include(house.titulo_anuncio)
    expect(response.body).not_to include(outside.titulo_anuncio)
  end

  it "filtra Vista Mar somente por imóveis com vista configurada" do
    sea_view = create_catalog_property(codigo: high_catalog_code(9), titulo_anuncio: "Filtro vista mar correto", caracteristicas: ["Vista Mar"])
    flag_view = create_catalog_property(codigo: high_catalog_code(9), titulo_anuncio: "Filtro vista mar flag", vista_frente_mar_flag: true)
    unrelated = create_catalog_property(codigo: high_catalog_code(8), titulo_anuncio: "Filtro sem vista mar", descricao_web: "Apartamento a poucos metros do mar")

    get admin_habitations_path(amenities: ["Vista Mar"])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(sea_view.titulo_anuncio)
    expect(response.body).to include(flag_view.titulo_anuncio)
    expect(response.body).not_to include(unrelated.titulo_anuncio)
  end

  it "não usa corretor_nome legado para casar o filtro explícito por corretor" do
    broker = create(:admin_user, name: "Corretora Amanda")
    matching_title = "Filtro corretor vínculo real #{SecureRandom.hex(6)}"
    legacy_title = "Filtro corretor nome legado #{SecureRandom.hex(6)}"

    create_catalog_property(titulo_anuncio: matching_title, admin_user_id: broker.id)
    create_catalog_property(titulo_anuncio: legacy_title, admin_user_id: admin.id, corretor_nome: broker.name)

    get admin_habitations_path(corretor_id: broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching_title)
    expect(response.body).not_to include(legacy_title)
  end

  it "considera filtros de atualização como filtros extras limpáveis" do
    create_catalog_property(data_atualizacao_crm: Time.zone.local(2026, 6, 12))

    get filter_inspector_admin_habitations_path(atualizacao_inicio: "2026-06-10", atualizacao_fim: "2026-06-16"),
        headers: turbo_frame_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("2 filtros")
    expect(response.body).to include("Limpar filtros avançados")

    document = Nokogiri::HTML(response.body)
    clear_href = document.at_css('a.ax-btn--ghost[href]')["href"]
    expect(clear_href).not_to include("atualizacao_inicio")
    expect(clear_href).not_to include("atualizacao_fim")
  end

  it "ignora filtros removidos do inspector enviados por URL antiga" do
    proprietor = create(:proprietor)
    visible_one = high_catalog_code(9)
    visible_two = high_catalog_code(9)
    create_catalog_property(
      codigo: visible_one,
      dormitorios_qtd: 1,
      face: "Sul",
      proprietor_id: nil,
      permuta_valor_cents: 100_000_00,
      address: { logradouro: "Rua Livre", bairro: "Nações" }
    )
    create_catalog_property(
      codigo: visible_two,
      dormitorios_qtd: 5,
      face: "Norte",
      proprietor_id: proprietor.id,
      permuta_valor_cents: 1_000_000_00,
      address: { logradouro: "Rua Antiga", bairro: "Centro" }
    )

    get admin_habitations_path(
      bairro: ["Centro"],
      face: "Norte",
      dorms: ["5"],
      proprietor_id: proprietor.id,
      permuta_min_value: "900000"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible_one)
    expect(response.body).to include(visible_two)
    expect(response.body).not_to include("Rua: Rua Antiga")
    expect(response.body).not_to include("Proprietário:")
  end

  it "ignora filtros administrativos enviados por URL para corretor" do
    agent = create(:admin_user, email: "agent-admin-filter-#{SecureRandom.hex(6)}@salute.test", profile: default_agent_profile)
    sign_in agent

    visible_without_admin_flag = high_catalog_code(9)
    visible_with_admin_flag = high_catalog_code(9)
    create_catalog_property(codigo: visible_without_admin_flag, titulo_anuncio: "Filtro administrativo ignorado #{SecureRandom.hex(6)}", destaque_web_flag: false, regiao_foco: "Não")
    create_catalog_property(codigo: visible_with_admin_flag, titulo_anuncio: "Filtro administrativo permitido #{SecureRandom.hex(6)}", destaque_web_flag: true, regiao_foco: "Centro")

    get admin_habitations_path(ownership: "all", destaque_web: "1", regiao_foco: "Sim")

    expect(response).to have_http_status(:ok)
    expect(response.body.include?(visible_without_admin_flag)).to eq(true)
    expect(response.body.include?(visible_with_admin_flag)).to eq(true)
    expect(response.body).not_to include("Destaque Web: Sim")
    expect(response.body).not_to include("Região foco?: Sim")
  end
end
