# frozen_string_literal: true

module AttributeOptions
  module HabitationFeatureNormalizer
    FEATURE_LABELS = {
      "adega" => "Adega",
      "agua quente" => "Água quente",
      "alarme" => "Alarme",
      "aquecimento a gas" => "Aquecimento a gás",
      "aquecimento gas" => "Aquecimento a gás",
      "ar central" => "Ar central",
      "ar condicionado" => "Ar-condicionado",
      "area de servico" => "Área de serviço",
      "area servico" => "Área de serviço",
      "armario embutido" => "Armário embutido",
      "armarios embutidos" => "Armário embutido",
      "armarios nos quartos" => "Armários nos quartos",
      "armarios quartos" => "Armários nos quartos",
      "banheira hidromassagem" => "Banheira hidromassagem",
      "banheiro auxiliar" => "Banheiro auxiliar",
      "banho auxiliar" => "Banheiro auxiliar",
      "banheiro social" => "Banheiro social",
      "banho social" => "Banheiro social",
      "bar" => "Bar",
      "bicicletario" => "Bicicletário",
      "canaletas no rodape" => "Canaletas no rodapé",
      "churrasqueira" => "Churrasqueira",
      "churrasqueira a carvao" => "Churrasqueira a carvão",
      "churrasqueira a gas" => "Churrasqueira a gás",
      "churrasqueira coletiva" => "Churrasqueira coletiva",
      "condominio fechado" => "Condomínio fechado",
      "copa" => "Copa",
      "copa cozinha" => "Copa/cozinha",
      "cozinha" => "Cozinha",
      "cozinha americana" => "Cozinha americana",
      "cozinha gourmet com churrasqueira" => "Cozinha gourmet com churrasqueira",
      "cozinha planejada" => "Cozinha planejada",
      "deck" => "Deck",
      "dependencia de empregada" => "Dependência de empregada",
      "dependencia empregada" => "Dependência de empregada",
      "dependenciade empregada" => "Dependência de empregada",
      "despensa" => "Despensa",
      "diferenciado" => "Diferenciado",
      "dormitorio com armario" => "Dormitório com armário",
      "dormitorio com armarios" => "Dormitório com armários",
      "duplex" => "Duplex",
      "edicula" => "Edícula",
      "escritorio" => "Escritório",
      "espera split" => "Espera split",
      "estar intimo" => "Estar íntimo",
      "fechadura digital" => "Fechadura digital",
      "forro" => "Forro",
      "frente mar" => "Frente mar",
      "garden" => "Garden",
      "gas central" => "Gás central",
      "gradeado" => "Gradeado",
      "hall entrada" => "Hall de entrada",
      "hidromassagem" => "Hidromassagem",
      "home theater" => "Home theater",
      "jardim inverno" => "Jardim de inverno",
      "lareira" => "Lareira",
      "lavabo" => "Lavabo",
      "living" => "Living",
      "living hall" => "Living hall",
      "living lavabo" => "Lavabo",
      "mezanino" => "Mezanino",
      "mobiliado" => "Mobiliado",
      "mobiliado decorado" => "Mobiliado decorado",
      "monitoramento" => "Monitoramento",
      "pet place" => "Pet place",
      "piscina" => "Piscina",
      "piscina coletiva" => "Piscina coletiva",
      "piso elevado" => "Piso elevado",
      "quadra mar" => "Quadra mar",
      "quadra poliesportiva" => "Quadra poliesportiva",
      "quintal" => "Quintal",
      "reformado" => "Reformado",
      "sacada" => "Sacada",
      "sacada aberta" => "Sacada aberta",
      "sacada com churrasqueira" => "Sacada com churrasqueira",
      "sacada fechada" => "Sacada fechada",
      "sacada integrada" => "Sacada integrada",
      "sala armarios" => "Sala com armários",
      "sala com armarios" => "Sala com armários",
      "sala estar" => "Sala de estar",
      "sala de estar" => "Sala de estar",
      "sala jantar" => "Sala de jantar",
      "sala de jantar" => "Sala de jantar",
      "sala fitness" => "Sala fitness",
      "sala t v" => "Sala de TV",
      "sala tv" => "Sala de TV",
      "salao de festas" => "Salão de festas",
      "sauna" => "Sauna",
      "sem mobilia" => "Sem mobília",
      "semi mobiliado" => "Semi mobiliado",
      "sol da manha" => "Sol da manhã",
      "sol da tarde" => "Sol da tarde",
      "sol o dia todo" => "Sol o dia todo",
      "split" => "Split",
      "suite master" => "Suíte master",
      "terraco" => "Terraço",
      "triplex" => "Triplex",
      "vigia externo" => "Vigia externo",
      "vigia interno" => "Vigia interno",
      "vista mar" => "Vista mar",
      "vista panoramica" => "Vista panorâmica",
      "vista para o mar" => "Vista para o mar",
      "vitrine" => "Vitrine",
      "wc empregada" => "WC empregada",
      "w c empregada" => "WC empregada"
    }.freeze

    INFRASTRUCTURE_LABELS = FEATURE_LABELS.merge(
      "agua" => "Água",
      "aquecimento central" => "Aquecimento central",
      "box de praia" => "Box de praia",
      "brinquedoteca" => "Brinquedoteca",
      "churrasqueira condominio" => "Churrasqueira condomínio",
      "circuito fechado t v" => "Circuito fechado TV",
      "circuito fechado tv" => "Circuito fechado TV",
      "circuito interno tv" => "Circuito interno TV",
      "deposito" => "Depósito",
      "elevador" => "Elevador",
      "elevador com" => "Elevador",
      "elevador servico" => "Elevador de serviço",
      "empresa de monitoramento" => "Empresa de monitoramento",
      "energia eletrica" => "Energia elétrica",
      "energia trifasica" => "Energia trifásica",
      "entrada servico independente" => "Entrada de serviço independente",
      "espaco gourmet" => "Espaço gourmet",
      "estacionamento" => "Estacionamento",
      "estacionamento visitantes" => "Estacionamento visitantes",
      "gerador energia" => "Gerador de energia",
      "guarita" => "Guarita",
      "heliponto" => "Heliponto",
      "interfone" => "Interfone",
      "jardim" => "Jardim",
      "lavanderia" => "Lavanderia",
      "pavimentacao" => "Pavimentação",
      "pilotis" => "Pilotis",
      "piscina aquecida" => "Piscina aquecida",
      "piscina infantil" => "Piscina infantil",
      "playground" => "Playground",
      "poco artesiano" => "Poço artesiano",
      "portaria" => "Portaria",
      "portaria 24h" => "Portaria 24h",
      "portaria 24hs" => "Portaria 24h",
      "portaria24 hrs" => "Portaria 24h",
      "porteiro eletronico" => "Porteiro eletrônico",
      "possui viabilidade" => "Possui viabilidade",
      "quadra esportes" => "Quadra de esportes",
      "quadra tenis" => "Quadra de tênis",
      "quiosque" => "Quiosque",
      "rede esgoto" => "Rede de esgoto",
      "sala de recepcao" => "Sala de recepção",
      "sala ginastica" => "Sala fitness",
      "sala jogos" => "Sala de jogos",
      "salao festas" => "Salão de festas",
      "salao jogos" => "Salão de jogos",
      "sauna condominio" => "Sauna condomínio",
      "seguranca patrimonial" => "Segurança patrimonial",
      "spa" => "Spa",
      "terraco coletivo" => "Terraço coletivo",
      "terraco col" => "Terraço coletivo",
      "tubulacao" => "Tubulação",
      "vigilancia24 horas" => "Vigilância 24h",
      "zelador" => "Zelador"
    ).freeze

    module_function

    def label(value, category: "feature")
      raw = value.to_s.strip
      return if raw.blank?

      labels = category.to_s == "infrastructure" ? INFRASTRUCTURE_LABELS : FEATURE_LABELS
      labels[key(raw)] || raw.tr("_", " ").downcase.squish.capitalize
    end

    def key(value)
      I18n.transliterate(value.to_s.tr("_", " "))
          .downcase
          .gsub(/[^a-z0-9]+/, " ")
          .squish
    end

    def normalize_list(values, category: "feature")
      Array(values)
        .flatten
        .filter_map { |value| label(value, category: category) }
        .index_by { |value| key(value) }
        .values
    end

    def normalize_hash(hash)
      normalized = {}

      hash.each do |raw_key, raw_value|
        canonical = label(raw_value.presence || raw_key, category: "feature")
        next if canonical.blank?

        normalized[canonical] = canonical
      end

      normalized
    end
  end
end
