# Modelos para começar uma página nova: cada um é só uma lista de blocos com texto de exemplo
# (que se identifica como exemplo para não ir ao ar por esquecimento).
module LandingPages
  module Templates
    Template = Struct.new(:key, :label, :icon, :description, :blocks, keyword_init: true)

    ALL = [
      Template.new(
        key: "showcase", label: "Seleção de imóveis", icon: "buildings",
        description: "Lista filtrada com os filtros do visitante. É o modo vitrine de sempre.",
        blocks: [{ block_type: "property_showcase", data: { "visitor_filters" => true } }]
      ),
      Template.new(
        key: "institutional", label: "Página institucional", icon: "file-earmark-text",
        description: "Capa, texto e um botão de contato. Sem lista de imóveis.",
        blocks: [
          { block_type: "cover", data: { "title" => "Título da sua página", "subtitle" => "Escreva aqui uma frase de apoio (exemplo, edite).", "align" => "center" } },
          { block_type: "text", data: { "heading" => "Sobre nós", "body" => "<p>Escreva aqui o texto da página (exemplo, edite).</p>" } },
          { block_type: "button", data: { "label" => "Fale conosco", "url" => "/contato" } }
        ]
      ),
      Template.new(
        key: "hybrid", label: "Híbrida", icon: "layout-text-sidebar-reverse",
        description: "Capa, texto de apresentação e a seleção de imóveis logo abaixo.",
        blocks: [
          { block_type: "cover", data: { "title" => "Título da sua página", "subtitle" => "Escreva aqui uma frase de apoio (exemplo, edite).", "align" => "center" } },
          { block_type: "text", data: { "heading" => "Apresentação", "body" => "<p>Conte por que esta seleção existe (exemplo, edite).</p>" } },
          { block_type: "property_showcase", data: { "heading" => "Imóveis selecionados", "visitor_filters" => true } }
        ]
      ),
      Template.new(
        key: "demo", label: "Demonstração", icon: "layout-text-window",
        description: "Exemplo genérico com apresentação, três colunas e contato. Edite antes de publicar.",
        blocks: [
          { block_type: "gallery", data: { "columns" => 1, "layout_width" => "page", "items" => [{ "image" => "https://images.pexels.com/photos/16495410/pexels-photo-16495410.jpeg?auto=compress&cs=tinysrgb&w=1600&h=500&fit=crop", "alt" => "Arquitetura contemporânea de um edifício comercial" }] } },
          { block_type: "section", data: { "heading" => "Conheça nossa imobiliária", "subtitle" => "Conectamos pessoas, lugares e novos começos.", "columns" => 2, "spacing" => "wide", "align" => "center" } },
          { block_type: "text", data: { "heading" => "Mais do que imóveis. Histórias para viver.", "body" => "<p>Acreditamos que escolher um imóvel é escolher o cenário dos próximos capítulos da vida. Por isso, nossa proposta é ouvir, orientar e acompanhar cada decisão com cuidado.</p><p>Reunimos conhecimento do mercado e atendimento próximo para ajudar quem deseja comprar, vender ou alugar.</p>", "expandable" => true, "more_body" => "<p>Este é um conteúdo de demonstração. Conte aqui a história real da sua empresa, sua região de atuação e os diferenciais que fazem parte do seu trabalho.</p>", "column" => 1 } },
          { block_type: "gallery", data: { "columns" => 1, "column" => 2, "offset_y" => -70, "layer" => 1, "items" => [{ "image" => "https://images.pexels.com/photos/16495410/pexels-photo-16495410.jpeg?auto=compress&cs=tinysrgb&w=900&h=700&fit=crop", "alt" => "Detalhes de fachada de arquitetura moderna", "title" => "Espaços que inspiram novos começos" }] } },
          { block_type: "section", data: { "columns" => 1, "spacing" => "compact" } },
          { block_type: "indicators", data: { "heading" => "Um atendimento completo", "layout_width" => "page", "columns" => 3, "items" => [{ "label" => "01", "title" => "Escutar", "text" => "Entender seu momento e suas prioridades." }, { "label" => "02", "title" => "Orientar", "text" => "Apresentar possibilidades com clareza." }, { "label" => "03", "title" => "Acompanhar", "text" => "Estar presente em cada etapa da negociação." }] } },
          { block_type: "section", data: { "heading" => "O que nos move", "columns" => 2, "background" => "soft", "spacing" => "wide", "align" => "center" } },
          { block_type: "gallery", data: { "column" => 1, "columns" => 1, "items" => [{ "image" => "https://images.pexels.com/photos/34725826/pexels-photo-34725826.jpeg?auto=compress&cs=tinysrgb&w=1000&h=850&fit=crop", "alt" => "Edifício de vidro visto de baixo, sob o céu azul" }] } },
          { block_type: "cards", data: { "column" => 2, "columns" => 1, "items" => [{ "title" => "Missão", "text" => "Ajudar pessoas a encontrar imóveis alinhados aos seus planos, com informação e atendimento responsável.", "icon" => "bullseye" }, { "title" => "Visão", "text" => "Construir relações duradouras e ser uma referência de confiança na região em que atuamos.", "icon" => "eye" }, { "title" => "Valores", "text" => "Transparência, respeito, escuta e compromisso com cada cliente.", "icon" => "heart" }] } },
          { block_type: "section", data: { "heading" => "Para cada momento, um caminho", "subtitle" => "Explore as possibilidades com nossa equipe.", "columns" => 1, "spacing" => "wide" } },
          { block_type: "cards", data: { "columns" => 3, "items" => [{ "title" => "Comprar", "text" => "Encontre um espaço para morar ou investir.", "icon" => "house", "url" => "/imoveis" }, { "title" => "Vender", "text" => "Apresente seu imóvel e converse sobre os próximos passos.", "icon" => "key", "url" => "/contato" }, { "title" => "Alugar", "text" => "Descubra opções para uma nova fase da vida.", "icon" => "buildings", "url" => "/contato" }] } },
          { block_type: "section", data: { "heading" => "Vamos conversar sobre seu próximo passo?", "subtitle" => "Nossa equipe está pronta para ouvir você.", "columns" => 1, "background" => "primary", "spacing" => "wide" } },
          { block_type: "button", data: { "label" => "Fale com nossa equipe", "url" => "/contato", "button_icon" => "chat-dots", "align" => "center" } },
          { block_type: "section", data: { "columns" => 1, "spacing" => "compact" } },
          { block_type: "text", data: { "body" => "<p>Página de demonstração: textos e imagens ilustrativos. Substitua pelas informações reais da sua empresa antes de publicar. Fotografias: Nadzeya Klim e Anshu Kumar / Pexels.</p>" } }
        ]
      ),
      Template.new(key: "blank", label: "Em branco", icon: "plus-square-dotted", description: "Começa vazia: você adiciona os blocos.", blocks: [])
    ].freeze

    BY_KEY = ALL.index_by(&:key).freeze

    def self.find(key) = BY_KEY[key.to_s] || BY_KEY.fetch("blank")
  end
end
