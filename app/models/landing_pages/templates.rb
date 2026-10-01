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
      Template.new(key: "blank", label: "Em branco", icon: "plus-square-dotted", description: "Começa vazia: você adiciona os blocos.", blocks: [])
    ].freeze

    BY_KEY = ALL.index_by(&:key).freeze

    def self.find(key) = BY_KEY[key.to_s] || BY_KEY.fetch("showcase")
  end
end
