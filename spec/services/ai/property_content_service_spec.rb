require "rails_helper"

RSpec.describe Ai::PropertyContentService do
  describe "payload de geração" do
    it "inclui parâmetros configuráveis da OpenAI" do
      habitation = create(:habitation)
      Setting.set(described_class::TEMPERATURE_SETTING, "0.33", "Temperature", tenant: habitation.tenant)
      Setting.set(described_class::TOP_P_SETTING, "0.77", "Top P", tenant: habitation.tenant)
      Setting.set(described_class::FREQUENCY_PENALTY_SETTING, "0.44", "Frequency penalty", tenant: habitation.tenant)
      Setting.set(described_class::PRESENCE_PENALTY_SETTING, "0.22", "Presence penalty", tenant: habitation.tenant)

      payload = described_class.new(habitation).send(:openai_payload)

      expect(payload).to include(
        temperature: 0.33,
        top_p: 0.77,
        frequency_penalty: 0.44,
        presence_penalty: 0.22
      )
    end

    it "inclui todos os campos de endereço relevantes para a IA" do
      habitation = create(
        :habitation,
        bloco: "B",
        lote: "12",
        quadra: "Q7",
        public_map_display_mode: "approximate",
        public_street_view_mode: "disabled"
      )
      habitation.address.update!(
        tipo_endereco: "Avenida",
        logradouro: "João da Costa",
        numero: "123",
        complemento: "Distrito Rio do Meio",
        bairro: "Distrito de Águas Brancas",
        bairro_comercial: "Águas Brancas",
        cidade: "Camboriú",
        uf: "SC",
        cep: "88340-000",
        pais: "Brasil",
        latitude: -27.024,
        longitude: -48.653,
        imediacoes: ["Mercado", "Escola"]
      )

      payload = described_class.new(habitation).send(:property_payload)

      expect(payload.fetch(:endereco)).to include(
        tipo_endereco: "Avenida",
        logradouro: "João da Costa",
        numero: "123",
        complemento: "Distrito Rio do Meio",
        bairro: "Distrito de Águas Brancas",
        bairro_comercial: "Águas Brancas",
        cidade: "Camboriú",
        uf: "SC",
        cep: "88340-000",
        pais: "Brasil",
        bloco: "B",
        lote: "12",
        quadra: "Q7",
        imediacoes: ["Mercado", "Escola"],
        localizacao_publica: "approximate",
        vista_da_rua: "disabled"
      )
    end

    it "inclui dados factuais do imóvel e do empreendimento para reduzir invenções" do
      development = create(
        :habitation,
        tipo: "Empreendimento",
        categoria: "Empreendimento",
        codigo: "DEV-AI-1",
        nome_empreendimento: "Residencial Atlântico",
        titulo_anuncio: "Residencial Atlântico",
        bairro: "Barra Sul",
        bairro_comercial: "Orla Sul",
        descricao_empreendimento: "<p>Lazer com piscina e salão de festas.</p>",
        infra_estrutura: ["Piscina", "Salão de festas"],
        caracteristica_unica: ["Lazer no rooftop"],
        construtora: "Construtora Mar",
        tipo_fachada: "Pastilhada",
        data_entrega: Date.new(2027, 5, 1),
        ano_construcao: 2026,
        andares_qtd: 38,
        aptos_andar: 4,
        aptos_edificio: 152,
        elevadores_qtd: 3
      )
      habitation = create(
        :habitation,
        codigo_empreendimento: development.codigo,
        nome_empreendimento: development.nome_empreendimento,
        bloco: "1201",
        andar: 12,
        dormitorios_qtd: 3,
        suites_qtd: 2,
        demi_suites_qtd: 1,
        banheiros_qtd: 4,
        salas_qtd: 2,
        varandas_qtd: 1,
        vagas_qtd: 2,
        tipo_vaga: "Privativa",
        numero_box: "B12",
        area_privativa_m2: 128.45,
        area_total_m2: 180.25,
        area_terreno_m2: 400.0,
        area_util_m2: 124.0,
        dimensoes_terreno: "Frente: 20 m | Fundos: 20 m",
        topografia: "Plana",
        valor_venda_cents: 1_750_000_00,
        valor_locacao_cents: 8_500_00,
        valor_total_aluguel_cents: 10_200_00,
        valor_condominio_cents: 1_200_00,
        valor_iptu_cents: 500_00,
        valor_por_m2_cents: 13_625_00,
        valor_promocional_cents: 1_690_000_00,
        valor_venda_anterior_cents: 1_850_000_00,
        valor_locacao_anterior_cents: 9_000_00,
        mobiliado_flag: true,
        decorado_flag: true,
        quadra_mar_flag: true,
        vista_frente_mar_flag: true,
        frente_mar_avenida_atlantica_flag: false,
        aceita_permuta_flag: true,
        aceita_financiamento_flag: true,
        aceita_parcelamento_flag: true,
        ocupacao_status: "Desocupado",
        estado_conservacao: "Novo",
        construtora: "Construtora Unidade",
        tipo_fachada: "Vidro",
        data_entrega: Date.new(2027, 5, 1),
        ano_construcao: 2025,
        andares_qtd: 40,
        aptos_andar: 2,
        aptos_edificio: 80,
        elevadores_qtd: 4,
        face: "Norte",
        caracteristicas: ["Churrasqueira a carvão"],
        infra_estrutura: ["Academia"],
        caracteristica_unica: ["Vista para o mar"],
        foto_classificacao: "Profissional",
        observacoes_visitas: "Distância da praia: 350 m"
      )

      payload = described_class.new(habitation).send(:property_payload)

      expect(payload).to include(
        nome_empreendimento: "Residencial Atlântico",
        codigo_empreendimento: "DEV-AI-1",
        unidade_numero: "1201",
        salas: 2,
        varandas: 1,
        tipo_vaga: "Privativa",
        numero_box: "B12",
        andar: 12,
        area_terreno_m2: 400.0,
        area_util_m2: 124.0,
        dimensoes_terreno: "Frente: 20 m | Fundos: 20 m",
        topografia: "Plana",
        valor_condominio_cents: 1_200_00,
        valor_iptu_cents: 500_00,
        valor_por_m2_cents: 13_625_00,
        valor_promocional_cents: 1_690_000_00,
        valor_venda_anterior_cents: 1_850_000_00,
        valor_locacao_anterior_cents: 9_000_00,
        aceita_permuta: true,
        aceita_financiamento: true,
        aceita_parcelamento: true,
        ocupacao: "Desocupado",
        estado_conservacao: "Novo",
        construtora: "Construtora Unidade",
        tipo_fachada: "Vidro",
        data_entrega: Date.new(2027, 5, 1),
        ano_construcao: 2025,
        andares: 40,
        aptos_por_andar: 2,
        aptos_no_edificio: 80,
        elevadores: 4,
        distancia_praia_m: "350",
        face: "Norte"
      )
      expect(payload.fetch(:midia)).to include(
        possui_fotos: true,
        classificacao_fotos: "Profissional",
        usa_fotos_empreendimento: true
      )
      expect(payload.fetch(:empreendimento)).to include(
        codigo: "DEV-AI-1",
        nome: "Residencial Atlântico",
        descricao: "Lazer com piscina e salão de festas.",
        infraestrutura: include("Piscina", "Salão de festas"),
        destaques: ["Lazer no rooftop"],
        construtora: "Construtora Mar",
        tipo_fachada: "Pastilhada",
        data_entrega: Date.new(2027, 5, 1),
        ano_construcao: 2026,
        andares: 38,
        aptos_por_andar: 4,
        aptos_no_edificio: 152,
        elevadores: 3
      )
    end
  end
end
