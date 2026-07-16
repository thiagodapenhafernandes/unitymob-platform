require "rails_helper"

RSpec.describe "Admin habitation catalog filters", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "admin-#{SecureRandom.hex(8)}@salute.test") }
  let(:turbo_frame_headers) { { "Turbo-Frame" => "habitations_filter_inspector" } }

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

  def expect_catalog_filter(label, params, matching_attrs:, nonmatching_attrs:, matching_address: nil, nonmatching_address: nil)
    habitation_ids = admin.tenant.habitations.ids
    Address.where(addressable_type: "Habitation", addressable_id: habitation_ids).delete_all if habitation_ids.any?
    Habitation.where(id: habitation_ids).delete_all if habitation_ids.any?

    matching_title = matching_attrs[:titulo_anuncio] || "Filtro #{label} match #{SecureRandom.hex(6)}"
    nonmatching_title = nonmatching_attrs[:titulo_anuncio] || "Filtro #{label} miss #{SecureRandom.hex(6)}"
    create_catalog_property({ titulo_anuncio: matching_title }.merge(matching_attrs), address: matching_address)
    create_catalog_property({ titulo_anuncio: nonmatching_title }.merge(nonmatching_attrs), address: nonmatching_address)

    get admin_habitations_path(params)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching_title), "esperava encontrar imóvel para filtro #{label}"
    expect(response.body).not_to include(nonmatching_title), "filtro #{label} deixou passar imóvel incompatível"
  end

  it "mantém compatibilidade do filtro legado exibir_no_site_salute usando a flag genérica do site" do
    matching_title = "Filtro legado site match #{SecureRandom.hex(6)}"
    nonmatching_title = "Filtro legado site miss #{SecureRandom.hex(6)}"
    create_catalog_property(titulo_anuncio: matching_title, exibir_no_site_flag: true)
    create_catalog_property(titulo_anuncio: nonmatching_title, exibir_no_site_flag: false)

    get admin_habitations_path(exibir_no_site_salute: "1")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching_title)
    expect(response.body).not_to include(nonmatching_title)
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
    proprietor = create(:proprietor, name: "Proprietário Filtro")
    create_catalog_property(codigo: "EMP-900", tipo: "Empreendimento", categoria: "Empreendimento", nome_empreendimento: "Empreendimento 900")
    create_catalog_property(codigo: "EMP-100", tipo: "Empreendimento", categoria: "Empreendimento", nome_empreendimento: "Empreendimento 100")

    scalar_filter_cases = [
      ["codigo", { codigo: "COD-UNICO" }, { codigo: "COD-UNICO" }, { codigo: "COD-UNICO-#{SecureRandom.hex(3)}" }],
      ["q", { q: "Vista Alpha" }, { titulo_anuncio: "Filtro q match Vista Alpha #{SecureRandom.hex(6)}" }, { titulo_anuncio: "Filtro q miss Beta #{SecureRandom.hex(6)}" }],
      ["status", { status: "Aluguel" }, { status: "Aluguel", valor_locacao_cents: 450_000 }, { status: "Venda" }],
      ["categoria", { categoria: "Terreno" }, { categoria: "Terreno" }, { categoria: "Apartamento" }],
      ["numero", { numero: "505" }, { numero: "505" }, { numero: "808" }],
      ["cep", { cep: "88330-590" }, { cep: "88330-590" }, { cep: "88000-000" }],
      ["cidade", { cidade: "Itapema" }, { cidade: "Itapema" }, { cidade: "Balneário Camboriú" }],
      ["bairro_comercial", { bairro_comercial: "Meia Praia" }, { bairro_comercial: "Meia Praia" }, { bairro_comercial: "Centro" }],
      ["situacao", { situacao: "Novo" }, { situacao: "Novo" }, { situacao: "Usado" }],
      ["promotion_status", { promotion_status: "with_promo" }, { valor_venda_cents: 900_000_00, valor_venda_anterior_cents: 1_000_000_00 }, { valor_venda_cents: 900_000_00, valor_venda_anterior_cents: nil }],
      ["accepts_exchange", { accepts_exchange: "1" }, { aceita_permuta_flag: true }, { aceita_permuta_flag: false }],
      ["key_location", { key_location: "Portaria" }, { key_location: "Portaria" }, { key_location: "Zelador" }],
      ["salute_rental_management", { salute_rental_management: "1" }, { salute_rental_management_flag: true }, { salute_rental_management_flag: false }],
      ["face", { face: "Norte" }, { face: "Norte" }, { face: "Sul" }],
      ["ocupacao_status", { ocupacao_status: "Desocupado" }, { ocupacao_status: "Desocupado" }, { ocupacao_status: "Ocupado" }],
      ["estado_conservacao", { estado_conservacao: "Novo" }, { estado_conservacao: "Novo" }, { estado_conservacao: "Usado" }],
      ["regiao_foco", { regiao_foco: "Sim" }, { regiao_foco: "Centro" }, { regiao_foco: "Não" }],
      ["banheiros", { banheiros: ["3"] }, { banheiros_qtd: 3 }, { banheiros_qtd: 1 }],
      ["dorms", { dorms: ["4"] }, { dormitorios_qtd: 4 }, { dormitorios_qtd: 2 }],
      ["suites", { suites: ["2"] }, { suites_qtd: 2 }, { suites_qtd: 0 }],
      ["vagas", { vagas: ["3"] }, { vagas_qtd: 3 }, { vagas_qtd: 1 }],
      ["area_total_min", { area_total_min: "180" }, { area_total_m2: 200 }, { area_total_m2: 120 }],
      ["area_total_max", { area_total_max: "150" }, { area_total_m2: 120 }, { area_total_m2: 220 }],
      ["area_privativa_min", { area_privativa_min: "90" }, { area_privativa_m2: 100 }, { area_privativa_m2: 70 }],
      ["area_privativa_max", { area_privativa_max: "80" }, { area_privativa_m2: 70 }, { area_privativa_m2: 120 }],
      ["destaque_web", { destaque_web: "1" }, { destaque_web_flag: true }, { destaque_web_flag: false }],
      ["festival_salute", { festival_salute: "1" }, { festival_salute_flag: true }, { festival_salute_flag: false }],
      ["exibir_no_site_salute", { exibir_no_site_salute: "1" }, { exibir_no_site_flag: true }, { exibir_no_site_flag: false }],
      ["tem_placa", { tem_placa: "1" }, { tem_placa_flag: true }, { tem_placa_flag: false }],
      ["exclusivo", { exclusivo: "1" }, { exclusivo_flag: true }, { exclusivo_flag: false }],
      ["somente_com_imagens", { somente_com_imagens: "1" }, { pictures: [{ "url" => "https://example.com/with.jpg" }] }, { pictures: [] }],
      ["somente_sem_imagens", { somente_sem_imagens: "1" }, { pictures: [] }, { pictures: [{ "url" => "https://example.com/with.jpg" }] }],
      ["somente_dwv", { somente_dwv: "1" }, { imovel_dwv: "Sim" }, { imovel_dwv: "Não" }],
      ["foto_classificacao", { foto_classificacao: ["Profissionais"] }, { foto_classificacao: "Profissionais" }, { foto_classificacao: "Aceitáveis" }],
      ["amenities", { amenities: ["Sacada"] }, { caracteristicas: ["Sacada"] }, { caracteristicas: ["Lavabo"] }],
      ["publicar_imovelweb_2", { publicar_imovelweb_2: "1" }, { publicar_imovelweb_2: true }, { publicar_imovelweb_2: false }],
      ["publicar_lais_ai", { publicar_lais_ai: "1" }, { publicar_lais_ai: true }, { publicar_lais_ai: false }],
      ["publicar_chaves_na_mao", { publicar_chaves_na_mao: "1" }, { publicar_chaves_na_mao: true }, { publicar_chaves_na_mao: false }],
      ["publicar_casa_mineira", { publicar_casa_mineira: "1" }, { publicar_casa_mineira: true }, { publicar_casa_mineira: false }],
      ["publicar_imovelweb", { publicar_imovelweb: "1" }, { publicar_imovelweb: true }, { publicar_imovelweb: false }],
      ["publicar_viva_real_vrsync", { publicar_viva_real_vrsync: "1" }, { publicar_viva_real_vrsync: true }, { publicar_viva_real_vrsync: false }],
      ["permuta_vehicle", { permuta_vehicle: "1" }, { aceita_permuta_veiculo_flag: true }, { aceita_permuta_veiculo_flag: false }],
      ["permuta_property", { permuta_property: "1" }, { aceita_permuta_imovel_flag: true }, { aceita_permuta_imovel_flag: false }],
      ["permuta_others", { permuta_others: "1" }, { aceita_permuta_outros_flag: true }, { aceita_permuta_outros_flag: false }],
      ["permuta_min_value", { permuta_min_value: "200000" }, { permuta_valor_cents: 250_000_00 }, { permuta_valor_cents: 100_000_00 }],
      ["permuta_location", { permuta_location: "Itajaí" }, { permuta_localizacao: "Itajaí Centro" }, { permuta_localizacao: "Itapema" }],
      ["permuta_min_dorms", { permuta_min_dorms: "3" }, { permuta_dormitorios_qtd: 3 }, { permuta_dormitorios_qtd: 1 }],
      ["permuta_min_suites", { permuta_min_suites: "2" }, { permuta_suites_qtd: 2 }, { permuta_suites_qtd: 0 }],
      ["permuta_min_garagens", { permuta_min_garagens: "2" }, { permuta_garagens_qtd: 2 }, { permuta_garagens_qtd: 0 }],
      ["captacao_inicio", { captacao_inicio: "2026-06-10" }, { data_cadastro_crm: Time.zone.local(2026, 6, 20) }, { data_cadastro_crm: Time.zone.local(2026, 6, 1) }],
      ["captacao_fim", { captacao_fim: "2026-06-10" }, { data_cadastro_crm: Time.zone.local(2026, 6, 9) }, { data_cadastro_crm: Time.zone.local(2026, 6, 12) }],
      ["atualizacao_inicio", { atualizacao_inicio: "2026-06-10" }, { data_atualizacao_crm: Time.zone.local(2026, 6, 20) }, { data_atualizacao_crm: Time.zone.local(2026, 6, 1) }],
      ["atualizacao_fim", { atualizacao_fim: "2026-06-10" }, { data_atualizacao_crm: Time.zone.local(2026, 6, 9) }, { data_atualizacao_crm: Time.zone.local(2026, 6, 12) }],
      ["min_price", { min_price: "800000" }, { valor_venda_cents: 900_000_00 }, { valor_venda_cents: 700_000_00, valor_locacao_cents: 0 }],
      ["max_price", { max_price: "800000" }, { valor_venda_cents: 700_000_00 }, { valor_venda_cents: 900_000_00, valor_locacao_cents: 0 }],
      ["empreendimento_codigo", { empreendimento_codigo: "Residencial Filtro" }, { nome_empreendimento: "Residencial Filtro" }, { nome_empreendimento: "Residencial Outro" }],
      ["proprietor_id", { proprietor_id: proprietor.id }, { proprietor_id: proprietor.id }, { proprietor_id: nil }]
    ]

    scalar_filter_cases.each do |label, params, matching_attrs, nonmatching_attrs|
      expect_catalog_filter(label, params, matching_attrs:, nonmatching_attrs:)
    end

    expect_catalog_filter(
      "logradouro",
      { logradouro: "Avenida Brasil" },
      matching_attrs: {},
      nonmatching_attrs: {},
      matching_address: { tipo_endereco: "Avenida", logradouro: "Brasil", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" },
      nonmatching_address: { tipo_endereco: "Rua", logradouro: "Central", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )

    expect_catalog_filter(
      "bairro",
      { bairro: ["Centro", "Barra Sul"] },
      matching_attrs: { bairro: "Barra Sul" },
      nonmatching_attrs: { bairro: "Nações" }
    )

    expect_catalog_filter(
      "corretor_id",
      { corretor_id: broker.id },
      matching_attrs: { admin_user_id: broker.id },
      nonmatching_attrs: { admin_user_id: admin.id }
    )
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
end
