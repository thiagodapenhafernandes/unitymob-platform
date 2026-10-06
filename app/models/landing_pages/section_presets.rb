module LandingPages
  # Composições compartilhadas entre a biblioteca do editor e os modelos de página.
  module SectionPresets
    Preset = Struct.new(:key, :label, :icon, :blocks, keyword_init: true)
    ALL = [
      Preset.new(key: "intro", label: "Texto + foto", icon: "layout-split", blocks: [
        { block_type: "section", data: { columns: 2, align: "center", spacing: "wide", heading: "Conheça nossa história" } },
        { block_type: "text", data: { column: "1", heading: "Pessoas e lugares conectados", body: "<p>Conte a história da sua empresa e o que torna seu atendimento especial. Texto de exemplo: substitua antes de publicar.</p>" } },
        { block_type: "image", data: { column: "2", alt: "Envie uma fotografia da sua equipe ou espaço", rounded: true } }
      ]),
      Preset.new(key: "benefits", label: "Benefícios", icon: "stars", blocks: [
        { block_type: "section", data: { columns: 1, background: "soft", spacing: "wide", heading: "Cuidado em cada detalhe" } },
        { block_type: "cards", data: { card_style: "outline", columns: 3, items: [
          { title: "Atendimento próximo", text: "Descreva como sua equipe acompanha o cliente.", icon: "people" },
          { title: "Conhecimento do mercado", text: "Apresente um diferencial real da sua empresa.", icon: "buildings" },
          { title: "Mais tranquilidade", text: "Explique o suporte oferecido em cada etapa.", icon: "shield-check" }
        ] } }
      ]),
      Preset.new(key: "numbers", label: "Números em destaque", icon: "123", blocks: [
        { block_type: "section", data: { columns: 1, spacing: "wide", heading: "Nossa experiência" } },
        { block_type: "indicators", data: { card_style: "highlight", items: [
          { label: "01", title: "Indicador", text: "Substitua por um número verificado." },
          { label: "02", title: "Indicador", text: "Substitua por um número verificado." },
          { label: "03", title: "Indicador", text: "Substitua por um número verificado." }
        ] } }
      ]),
      Preset.new(key: "steps", label: "Como funciona", icon: "list-ol", blocks: [
        { block_type: "section", data: { columns: 1, spacing: "wide", heading: "Como funciona" } },
        { block_type: "steps", data: { card_style: "outline", items: [
          { title: "Converse com a equipe", text: "Conte seus objetivos e tire suas dúvidas." },
          { title: "Conheça as possibilidades", text: "Avalie as opções com orientação." },
          { title: "Dê o próximo passo", text: "Descreva como sua empresa acompanha esta etapa." }
        ] } }
      ]),
      Preset.new(key: "testimonials", label: "Depoimentos", icon: "chat-quote", blocks: [
        { block_type: "section", data: { columns: 1, background: "soft", spacing: "wide", heading: "Histórias de quem confia" } },
        { block_type: "testimonials", data: { card_style: "outline", mobile_presentation: "carousel", items: [{ title: "Nome do cliente — exemplo", text: "Insira aqui um depoimento real, autorizado pelo cliente.", label: "Identificação" }] } }
      ]),
      Preset.new(key: "cta", label: "Chamada final", icon: "chat-dots", blocks: [
        { block_type: "section", data: { columns: 1, background: "dark", spacing: "wide", heading: "Vamos conversar sobre seu próximo passo?", subtitle: "Nossa equipe está pronta para ouvir você." } },
        { block_type: "button", data: { label: "Fale com nossa equipe", url: "/contato", icon: "chat-dots" } }
      ])
    ].freeze
    BY_KEY = ALL.index_by(&:key).freeze
    def self.blocks(*keys) = keys.flat_map { |key| BY_KEY.fetch(key).blocks.deep_dup }
  end
end
