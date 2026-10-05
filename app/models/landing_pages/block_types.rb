# Catálogo de blocos do construtor de páginas. Cada tipo declara seus campos (nome, tipo, limite, padrão):
# o editor do admin é desenhado a partir desta lista e `normalize` é a única porta de entrada dos dados
# (nada de JSON livre: campo desconhecido é descartado, valor é convertido e limitado).
module LandingPages
  module BlockTypes
    # Mesma lista que a landing aceitava no texto SEO (superset do que o editor Trix gera).
    RICH_TAGS = %w[p br a strong b em i u h1 h2 h3 h4 h5 ul ol li blockquote span div img table thead tbody tr td th hr].freeze
    RICH_ATTRIBUTES = %w[href title target rel src alt class].freeze

    # Filtros que definem quais imóveis a vitrine mostra (os mesmos de `Habitation.advanced_search`).
    FILTER_KEYS = %w[
      q category city neighborhood development property_codes transaction_type min_bedrooms min_suites min_parking
      target_price min_area opportunity characteristics caracteristica_unica status sort
    ].freeze

    Field = Struct.new(:name, :type, :label, :hint, :default, :options, :limit, :placeholder, :item_fields, keyword_init: true)

    Definition = Struct.new(:key, :label, :icon, :description, :fields, keyword_init: true) do
      def field(name) = fields.find { |field| field.name.to_s == name.to_s }

      def defaults
        fields.to_h { |field| [field.name.to_s, field.default] }
      end

      # Converte o que veio do formulário no formato guardado: só campos do tipo, cada um coagido e limitado.
      def normalize(raw)
        raw = (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h).stringify_keys
        fields.to_h { |field| [field.name.to_s, coerce(field, raw.key?(field.name.to_s) ? raw[field.name.to_s] : field.default)] }
      end

      private

      def coerce(field, value)
        case field.type
        when :items
          rows = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
          rows = rows.values if rows.is_a?(Hash)
          Array(rows).first(50).filter_map do |row|
            next unless row.is_a?(Hash)
            raw = row.to_h.stringify_keys
            item = field.item_fields.to_h { |child| [child.name.to_s, coerce(child, raw[child.name.to_s])] }
            item["image_key"] = "" if item["remove_image"]
            item unless item.values.all?(&:blank?)
          end
        when :https_image then value.to_s.strip.match?(%r{\Ahttps://[^\s"'<>]+\z}) ? value.to_s.strip.first(1000) : ""
        when :hidden then value.to_s.match?(/\A[a-zA-Z0-9_-]{1,80}\z/) ? value.to_s : ""
        when :icon then value.to_s.match?(/\A[a-z0-9-]{1,60}\z/) ? value.to_s : ""
        when :color then value.to_s.match?(/\A#[0-9a-fA-F]{6}\z/) ? value.to_s : field.default
        when :button_icon then value.to_s.match?(/\A[a-z0-9-]{1,60}\z/) ? value.to_s : ""
        when :public_form then value.to_i.positive? ? value.to_i : nil
        when :string then value.to_s.squish.first(field.limit || 200)
        when :text then value.to_s.strip.first(field.limit || 2000)
        when :rich then ActionController::Base.helpers.sanitize(value.to_s, tags: RICH_TAGS, attributes: RICH_ATTRIBUTES).strip
        when :select then field.options.map { |_label, option| option.to_s }.include?(value.to_s) ? value.to_s : field.default.to_s
        when :boolean then ActiveModel::Type::Boolean.new.cast(value) ? true : false
        when :integer then field.options.map { |_label, option| option.to_i }.include?(value.to_i) ? value.to_i : field.default
        when :range then value.to_i.clamp(*field.options)
        when :url then value.to_s.strip.match?(PublicHeaderMenu::URL_FORMAT) ? value.to_s.strip : ""
        when :embed then coerce_embed(value, field)
        when :filters then coerce_filters(value)
        end
      end

      # Aceita o endereço ou o código <iframe …> colado: guarda só o src.
      def coerce_embed(value, field)
        text = value.to_s.strip
        text = text[/<iframe[^>]*\ssrc\s*=\s*["']([^"']+)["']/i, 1] || text
        text.squish.first(field.limit || 500)
      end

      def coerce_filters(value)
        hash = (value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h).stringify_keys
        FILTER_KEYS.each_with_object({}) do |key, filters|
          raw = hash[key]
          raw = Array(raw).map { |item| item.to_s.strip }.compact_blank if raw.is_a?(Array)
          raw = raw.to_s.strip unless raw.is_a?(Array)
          filters[key] = raw unless raw.blank?
        end
      end
    end

    ALIGNS = [["Esquerda", "left"], ["Centro", "center"], ["Direita", "right"]].freeze

    # Largura do bloco na linha de colunas da página (só tem efeito quando a página tem 2 ou 3 colunas).
    SPANS = [["Linha inteira", "full"], ["1 coluna", "1"], ["2 colunas", "2"]].freeze
    SPAN_FIELD = Field.new(name: :span, type: :select, label: "Largura na linha", options: SPANS, default: "full",
                           hint: "Só vale em páginas com 2 ou 3 colunas. Blocos em coluna ficam lado a lado.")

    COLUMN_FIELD = Field.new(name: :column, type: :select, label: "Coluna dentro da seção", options: [["Coluna 1", "1"], ["Coluna 2", "2"], ["Coluna 3", "3"]], default: "1",
                             hint: "Vale depois de um bloco Seção. Mova os blocos para baixo da seção e escolha a coluna de cada um.")
    COLLECTIONS = {
      "cards" => ["Cards de conteúdo", "grid", "Serviços, áreas de atuação ou cidades com imagem, texto e link."],
      "indicators" => ["Indicadores", "123", "Números e legendas de experiência, clientes e resultados."],
      "testimonials" => ["Depoimentos", "chat-quote", "Depoimento, nome e identificação de quem falou."],
      "timeline" => ["Linha do tempo", "clock-history", "Ano, título e descrição dos marcos da empresa."],
      "partners" => ["Parceiros", "buildings", "Logos de parceiros com nome e link."],
      "team" => ["Equipe", "people", "Foto, nome, cargo e link de cada pessoa."],
      "gallery" => ["Galeria de imagens", "images", "Imagens com legenda e link, em grade ou carrossel."]
    }.freeze
    ITEM_FIELDS = [
      Field.new(name: :row_key, type: :hidden),
      Field.new(name: :image_key, type: :hidden),
      Field.new(name: :remove_image, type: :boolean, label: "Remover imagem enviada", default: false),
      Field.new(name: :title, type: :string, label: "Título / nome", limit: 160),
      Field.new(name: :label, type: :string, label: "Ano / número / cargo", limit: 120),
      Field.new(name: :text, type: :text, label: "Descrição / depoimento", limit: 3000),
      Field.new(name: :image, type: :https_image, label: "URL da imagem (https)", placeholder: "https://…"),
      Field.new(name: :alt, type: :string, label: "Descrição da imagem", limit: 160),
      Field.new(name: :url, type: :url, label: "Destino ao clicar", placeholder: "/pagina ou https://…"),
      Field.new(name: :icon, type: :icon, label: "Ícone Bootstrap (opcional)", placeholder: "Ex.: house, people, award")
    ].freeze

    RAW = [
      Definition.new(
        key: "form", label: "Formulário", icon: "ui-checks", description: "Formulário publicado da sua conta, exibido diretamente na página.",
        fields: [Field.new(name: :form_id, type: :public_form, label: "Formulário", default: nil)]
      ),
      Definition.new(
        key: "cover", label: "Capa", icon: "image", description: "Faixa de abertura com título, imagem de fundo e botão.",
        fields: [
          Field.new(name: :title, type: :string, label: "Título (H1)", limit: 120, default: "", placeholder: "Em branco usa o título da página"),
          Field.new(name: :subtitle, type: :text, label: "Subtítulo", limit: 280, default: ""),
          Field.new(name: :button_label, type: :string, label: "Texto do botão", limit: 40, default: ""),
          Field.new(name: :button_url, type: :url, label: "Destino do botão", default: "", hint: "/página, https://… ou #modal-ID de um formulário."),
          Field.new(name: :align, type: :select, label: "Alinhamento", options: ALIGNS, default: "center"),
          Field.new(name: :height, type: :select, label: "Altura da capa", options: [["Padrão", "auto"], ["Compacta", "compact"], ["Alta", "tall"]], default: "auto"),
          Field.new(name: :focus, type: :select, label: "Ponto focal da imagem", options: [["Centro", "center"], ["Topo", "top"], ["Base", "bottom"]], default: "center"),
          Field.new(name: :overlay, type: :integer, label: "Escurecer a imagem", options: [["Nada", 0], ["Leve", 25], ["Médio", 45], ["Forte", 65]], default: 45)
        ]
      ),
      Definition.new(
        key: "text", label: "Texto", icon: "text-paragraph", description: "Título e texto formatado (negrito, listas, links, imagens).",
        fields: [
          Field.new(name: :heading, type: :string, label: "Título da seção", limit: 120, default: ""),
          Field.new(name: :body, type: :rich, label: "Texto", default: ""),
          Field.new(name: :expandable, type: :boolean, label: "Texto complementar com Ver mais", default: false),
          Field.new(name: :more_body, type: :rich, label: "Texto complementar", default: ""),
          Field.new(name: :more_label, type: :string, label: "Texto de Ver mais", limit: 40, default: "Ver mais"),
          Field.new(name: :width, type: :select, label: "Largura", options: [["Estreita (leitura)", "narrow"], ["Larga", "wide"]], default: "narrow")
        ]
      ),
      Definition.new(
        key: "property_showcase", label: "Vitrine de imóveis", icon: "buildings",
        description: "Lista de imóveis filtrada pelo que você definir, com ordenação e paginação.",
        fields: [
          Field.new(name: :heading, type: :string, label: "Título da seção", limit: 120, default: ""),
          Field.new(name: :subtitle, type: :string, label: "Subtítulo", limit: 240, default: ""),
          Field.new(name: :filters, type: :filters, label: "Quais imóveis aparecem", default: {}),
          Field.new(name: :sort, type: :select, label: "Ordem padrão", default: "",
                    options: [["Padrão do site", ""], ["Mais recentes", "newest"], ["Maior preço", "price_desc"], ["Menor preço", "price_asc"]]),
          Field.new(name: :per_page, type: :integer, label: "Imóveis por página", options: [["6", 6], ["12", 12], ["24", 24]], default: 12),
          Field.new(name: :visitor_filters, type: :boolean, label: "Filtros do visitante e paginação", default: true,
                    hint: "Ligado: o visitante refina dentro desta seleção. Só uma vitrine por página pode ter."),
          Field.new(name: :show_count, type: :boolean, label: "Mostrar “N imóveis encontrados”", default: true)
        ]
      ),
      Definition.new(
        key: "button", label: "Botão", icon: "cursor", description: "Botão que leva a uma página, link externo ou abre um formulário (modal).",
        fields: [
          Field.new(name: :label, type: :string, label: "Texto do botão", limit: 40, default: "", placeholder: "Ex.: Fale com um corretor"),
          Field.new(name: :url, type: :url, label: "Destino", default: "", hint: "/página, https://… ou #modal-ID de um formulário."),
          Field.new(name: :style, type: :select, label: "Estilo", options: [["Principal", "primary"], ["Secundário", "secondary"], ["Contorno", "outline"]], default: "primary"),
          Field.new(name: :align, type: :select, label: "Alinhamento", options: ALIGNS, default: "center"),
          Field.new(name: :icon, type: :button_icon, label: "Ícone", default: ""),
          Field.new(name: :custom_colors, type: :boolean, label: "Personalizar cores do botão", default: false),
          Field.new(name: :text_color, type: :color, label: "Cor do texto", default: "#ffffff"),
          Field.new(name: :background_color, type: :color, label: "Cor de fundo", default: "#003344"),
          Field.new(name: :new_tab, type: :boolean, label: "Abrir em nova aba", default: false)
        ]
      ),
      Definition.new(
        key: "image", label: "Imagem", icon: "card-image", description: "Uma imagem com legenda e link opcionais.",
        fields: [
          Field.new(name: :alt, type: :string, label: "Texto alternativo", limit: 160, default: "", hint: "Descreve a imagem para quem não a enxerga e para o Google."),
          Field.new(name: :caption, type: :string, label: "Legenda", limit: 200, default: ""),
          Field.new(name: :link, type: :url, label: "Link ao clicar (opcional)", default: "", hint: "/página, https://… ou #modal-ID de um formulário."),
          Field.new(name: :fit, type: :select, label: "Tamanho", options: [["Preencher a largura", "fill"], ["Tamanho original", "natural"]], default: "fill"),
          Field.new(name: :rounded, type: :boolean, label: "Cantos arredondados", default: false)
        ]
      ),
      Definition.new(
        key: "video", label: "Vídeo (YouTube ou Vimeo)", icon: "play-btn", description: "Cole a URL do YouTube ou Vimeo. Vídeo responsivo, sem reprodução automática.",
        fields: [
          Field.new(name: :url, type: :embed, label: "URL do YouTube ou Vimeo", default: "", limit: 300, placeholder: "https://www.youtube.com/watch?v=…",
                    hint: "Aceita youtube.com/watch, youtu.be, /shorts, vimeo.com e códigos de incorporar."),
          Field.new(name: :click_to_play, type: :boolean, label: "Carregar o player somente ao clicar", default: false, hint: "Mantém a página leve até o visitante querer assistir."),
          Field.new(name: :title, type: :string, label: "Título do vídeo", limit: 120, default: "", hint: "Lido por leitores de tela."),
          Field.new(name: :caption, type: :string, label: "Legenda", limit: 200, default: "")
        ]
      ),
      Definition.new(
        key: "embed", label: "Conteúdo incorporado (iframe)", icon: "window-stack", description: "Mapa, calendário, tour virtual ou qualquer página https.",
        fields: [
          Field.new(name: :url, type: :embed, label: "Endereço ou código do iframe", default: "", limit: 500, placeholder: "https://…",
                    hint: "Só https. Pode colar o código <iframe …>: usamos o endereço dele."),
          Field.new(name: :title, type: :string, label: "Título do conteúdo", limit: 120, default: "", hint: "Lido por leitores de tela."),
          Field.new(name: :height, type: :integer, label: "Altura", options: [["Baixa (300 px)", 300], ["Média (450 px)", 450], ["Alta (600 px)", 600], ["Muito alta (800 px)", 800]], default: 450)
        ]
      )
    ].freeze

    SECTION = Definition.new(key: "section", label: "Seção com colunas", icon: "layout-three-columns", description: "Agrupa os blocos seguintes em até três colunas, até a próxima seção.", fields: [
      Field.new(name: :heading, type: :string, label: "Título da seção", limit: 120, default: ""),
      Field.new(name: :subtitle, type: :text, label: "Introdução", limit: 1000, default: ""),
      Field.new(name: :columns, type: :integer, label: "Colunas desta seção", options: [["1 coluna", 1], ["2 colunas", 2], ["3 colunas", 3]], default: 2),
      Field.new(name: :ratio, type: :select, label: "Proporção (duas colunas)", options: [["Iguais", "equal"], ["Primeira maior", "wide-first"], ["Segunda maior", "wide-last"]], default: "equal"),
      Field.new(name: :align, type: :select, label: "Alinhamento vertical", options: [["Topo", "start"], ["Centro", "center"], ["Base", "end"]], default: "start"),
      Field.new(name: :background, type: :select, label: "Fundo", options: [["Padrão", "plain"], ["Suave", "soft"], ["Cor principal da conta", "primary"]], default: "plain"),
      Field.new(name: :spacing, type: :select, label: "Espaçamento", options: [["Compacto", "compact"], ["Normal", "normal"], ["Amplo", "wide"]], default: "normal")
    ])
    REPEATED = COLLECTIONS.map do |key, (label, icon, description)|
      Definition.new(key: key, label: label, icon: icon, description: description, fields: [
        Field.new(name: :heading, type: :string, label: "Título da seção", limit: 120, default: ""),
        Field.new(name: :subtitle, type: :text, label: "Introdução", limit: 1000, default: ""),
        Field.new(name: :columns, type: :integer, label: "Colunas", options: [["1", 1], ["2", 2], ["3", 3]], default: 3),
        Field.new(name: :layout, type: :select, label: "Apresentação", options: [["Grade", "grid"], ["Carrossel com rolagem", "carousel"]], default: "grid"),
        Field.new(name: :items, type: :items, label: "Itens", default: [], item_fields: ITEM_FIELDS.map do |field|
          labels = {
            "indicators" => { title: "Legenda do indicador", label: "Número (ex.: +12 anos)", text: "Complemento" },
            "testimonials" => { title: "Nome da pessoa", label: "Identificação / cargo", text: "Depoimento" },
            "timeline" => { title: "Título do marco", label: "Ano", text: "Descrição do marco" },
            "partners" => { title: "Nome do parceiro", label: "Segmento", image: "URL do logo (https)" },
            "team" => { title: "Nome da pessoa", label: "Cargo", text: "Apresentação" },
            "gallery" => { title: "Legenda", label: "Identificação", text: "Descrição" }
          }.fetch(key, {})
          field.dup.tap { |copy| copy.label = labels.fetch(field.name, field.label) }
        end)
      ])
    end

    LAYOUT_FIELDS = [
      Field.new(name: :layout_width, type: :select, label: "Largura do bloco", options: [["Padrão do tema", "theme"], ["Toda a coluna", "column"], ["Toda a página", "page"]], default: "theme"),
      Field.new(name: :layout_height, type: :select, label: "Altura", options: [["Automática", "auto"], ["Altura mínima personalizada", "custom"], ["Altura da tela", "screen"]], default: "auto"),
      Field.new(name: :layout_min_height, type: :range, label: "Altura mínima (px)", options: [0, 1200], default: 0),
      Field.new(name: :offset_x, type: :range, label: "Deslocamento horizontal X (px)", options: [-200, 200], default: 0),
      Field.new(name: :offset_y, type: :range, label: "Deslocamento vertical Y (px)", options: [-300, 300], default: 0),
      Field.new(name: :layer, type: :range, label: "Camada", options: [0, 10], default: 0),
      Field.new(name: :mobile_layout, type: :boolean, label: "Personalizar posição e altura no mobile", default: false),
      Field.new(name: :mobile_offset_x, type: :range, label: "X no mobile (px)", options: [-40, 40], default: 0),
      Field.new(name: :mobile_offset_y, type: :range, label: "Y no mobile (px)", options: [-100, 100], default: 0),
      Field.new(name: :mobile_min_height, type: :range, label: "Altura mínima no mobile (px)", options: [0, 800], default: 0)
    ].freeze

    ALL = (RAW + [SECTION] + REPEATED).map { |definition| definition.tap { |item| item.fields = item.fields + [SPAN_FIELD, COLUMN_FIELD] + LAYOUT_FIELDS } }.freeze

    BY_KEY = ALL.index_by(&:key).freeze

    def self.keys = BY_KEY.keys

    def self.fetch(key) = BY_KEY.fetch(key.to_s)

    def self.find(key) = BY_KEY[key.to_s]

    def self.options = ALL.map { |definition| [definition.label, definition.key] }
  end
end
