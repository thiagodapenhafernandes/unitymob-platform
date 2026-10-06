# Catálogo de blocos do construtor de páginas. Cada tipo declara seus campos (nome, tipo, limite, padrão):
# o editor do admin é desenhado a partir desta lista e `normalize` é a única porta de entrada dos dados
# (nada de JSON livre: campo desconhecido é descartado, valor é convertido e limitado).
module LandingPages
  module BlockTypes
    # Mesma lista que a landing aceitava no texto SEO (superset do que o editor Trix gera).
    RICH_TAGS = %w[p br a strong b em i u del s pre code h1 h2 h3 h4 h5 ul ol li blockquote span div img table thead tbody tr td th hr].freeze
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
        value = field.default if (value.is_a?(Hash) || value.is_a?(Array)) && !%i[items filters].include?(field.type)
        case field.type
        when :element_order
          value.to_s.split(",").select { |key| key.match?(/\A[a-z][a-z0-9_-]{0,79}\z/) }.uniq.first(50).join(",")
        when :items
          rows = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
          rows = rows.values if rows.is_a?(Hash)
          Array(rows).first(50).filter_map do |row|
            next unless row.is_a?(Hash)
            raw = row.to_h.stringify_keys
            item = field.item_fields.to_h { |child| [child.name.to_s, coerce(child, raw.key?(child.name.to_s) ? raw[child.name.to_s] : child.default)] }
            item["image_key"] = "" if item["remove_image"]
            item unless item.reject { |key, _| key == "rating" || key.start_with?("element_") || key.match?(/color|border|background_|gradient|font_|text_opacity|text_(align|decoration|transform)|line_height|letter_spacing|backdrop/) }.values.all?(&:blank?)
          end
        when :https_image then value.to_s.strip.match?(%r{\Ahttps://[^\s"'<>]+\z}) ? value.to_s.strip.first(1000) : ""
        when :anchor then value.to_s.parameterize.first(80)
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
        when :url
          url = value.to_s.strip
          url.match?(PublicHeaderMenu::URL_FORMAT) || url.match?(/\A#[a-zA-Z][a-zA-Z0-9_-]{0,79}\z/) ? url : ""
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
      "steps" => ["Etapas", "list-ol", "Passo a passo com números, título e explicação."],
      "gallery" => ["Galeria de imagens", "images", "Imagens com legenda e link, em grade ou carrossel."]
    }.freeze
    ITEM_FIELDS = [
      Field.new(name: :row_key, type: :hidden),
      Field.new(name: :image_key, type: :hidden),
      Field.new(name: :remove_image, type: :boolean, label: "Remover imagem enviada", default: false),
      Field.new(name: :title, type: :string, label: "Título / nome", limit: 160),
      Field.new(name: :label, type: :string, label: "Ano / número / cargo", limit: 120),
      Field.new(name: :badge_icon, type: :button_icon, label: "Ícone do selo", default: ""), Field.new(name: :badge, type: :string, label: "Selo (opcional)", limit: 120),
      Field.new(name: :initials, type: :string, label: "Iniciais (depoimento)", limit: 4),
      Field.new(name: :rating, type: :range, label: "Estrelas (0 = ocultar)", default: 0, options: [0, 5]),
      Field.new(name: :text, type: :rich, label: "Descrição / depoimento", limit: 3000),
      Field.new(name: :image, type: :https_image, label: "URL da imagem (https)", placeholder: "https://…"),
      Field.new(name: :alt, type: :string, label: "Descrição da imagem", limit: 160),
      Field.new(name: :url, type: :url, label: "Destino ao clicar", placeholder: "/pagina ou https://…"),
      Field.new(name: :icon, type: :icon, label: "Ícone Bootstrap (opcional)", placeholder: "Ex.: house, people, award")
    ].freeze

    RAW = [
      Definition.new(
        key: "form", label: "Formulário", icon: "ui-checks", description: "Formulário publicado da sua conta, exibido diretamente na página.",
        fields: [Field.new(name: :form_id, type: :public_form, label: "Formulário", default: nil), Field.new(name: :form_style, type: :select, label: "Apresentação do formulário", options: [["Padrão atual", "inherit"], ["Editorial", "editorial"]], default: "inherit"), Field.new(name: :whatsapp_url, type: :url, label: "WhatsApp (opcional)", default: "", hint: "Use https://wa.me/ com o número da equipe. Oferece envio dos dados pelo WhatsApp."), Field.new(name: :badge_icon, type: :button_icon, label: "Ícone do selo", default: ""), Field.new(name: :badge, type: :string, label: "Selo de apoio", default: "", limit: 120)]
      ),
      Definition.new(
        key: "cover", label: "Capa", icon: "image", description: "Faixa de abertura com título, imagem de fundo e botão.",
        fields: [
          Field.new(name: :eyebrow, type: :string, label: "Etiqueta acima do título", default: "", limit: 80),
          Field.new(name: :badge_icon, type: :button_icon, label: "Ícone do selo", default: ""), Field.new(name: :badge, type: :string, label: "Selo abaixo da introdução", default: "", limit: 120),
          Field.new(name: :design, type: :select, label: "Composição da capa", options: [["Imagem de fundo", "background"], ["Texto e imagem lado a lado", "split"], ["Somente texto", "simple"]], default: "background"),
          Field.new(name: :secondary_icon, type: :button_icon, label: "Ícone da segunda ação", default: ""), Field.new(name: :secondary_label, type: :string, label: "Texto da segunda ação", limit: 40, default: ""),
          Field.new(name: :secondary_url, type: :url, label: "Destino da segunda ação", default: ""),
          Field.new(name: :title, type: :string, label: "Título (H1)", limit: 120, default: "", placeholder: "Em branco usa o título da página"),
          Field.new(name: :subtitle, type: :text, label: "Subtítulo", limit: 1000, default: ""),
          Field.new(name: :button_icon, type: :button_icon, label: "Ícone da ação", default: ""), Field.new(name: :button_label, type: :string, label: "Texto do botão", limit: 40, default: ""),
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
      Field.new(name: :eyebrow, type: :string, label: "Etiqueta da seção", limit: 80, default: ""),
      Field.new(name: :heading_rule, type: :boolean, label: "Divisor abaixo do título", default: false),
      Field.new(name: :heading, type: :string, label: "Título da seção", limit: 120, default: ""),
      Field.new(name: :subtitle, type: :text, label: "Introdução", limit: 1000, default: ""),
      Field.new(name: :columns, type: :integer, label: "Colunas desta seção", options: [["1 coluna", 1], ["2 colunas", 2], ["3 colunas", 3]], default: 2),
      Field.new(name: :mobile_order, type: :select, label: "Ordem das colunas no celular", options: [["Normal", "normal"], ["Invertida", "reverse"]], default: "normal"),
      Field.new(name: :ratio, type: :select, label: "Proporção (duas colunas)", options: [["Iguais", "equal"], ["Primeira maior", "wide-first"], ["Segunda maior", "wide-last"]], default: "equal"),
      Field.new(name: :align, type: :select, label: "Alinhamento vertical", options: [["Topo", "start"], ["Centro", "center"], ["Base", "end"]], default: "start"),
      Field.new(name: :background, type: :select, label: "Fundo", options: [["Padrão", "plain"], ["Suave", "soft"], ["Escuro", "dark"], ["Cor principal da conta", "primary"]], default: "plain"),
      Field.new(name: :spacing, type: :select, label: "Espaçamento", options: [["Compacto", "compact"], ["Normal", "normal"], ["Amplo", "wide"]], default: "normal")
    ])
    REPEATED = COLLECTIONS.map do |key, (label, icon, description)|
      Definition.new(key: key, label: label, icon: icon, description: description, fields: [
        Field.new(name: :heading, type: :string, label: "Título da seção", limit: 120, default: ""),
        Field.new(name: :subtitle, type: :text, label: "Introdução", limit: 1000, default: ""),
        Field.new(name: :columns, type: :integer, label: "Colunas", options: [["1", 1], ["2", 2], ["3", 3], ["4", 4]], default: 3),
        Field.new(name: :layout, type: :select, label: "Apresentação", options: [["Grade", "grid"], ["Carrossel com rolagem", "carousel"], ["Etiquetas", "chips"]], default: "grid"),
        Field.new(name: :card_style, type: :select, label: "Estilo dos cards", options: [["Padrão atual", "legacy"], ["Sem fundo", "plain"], ["Fundo suave", "soft"], ["Contorno", "outline"], ["Destaque", "highlight"]], default: "legacy"),
        Field.new(name: :mobile_presentation, type: :select, label: "Apresentação no celular", options: [["Padrão atual", "inherit"], ["Empilhados", "stack"], ["Grade de duas colunas", "grid"], ["Carrossel", "carousel"]], default: "inherit"),
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

    def self.border_fields(prefix)
      key = prefix.present? ? "#{prefix}_" : ""
      [Field.new(name: "#{key}custom_border".to_sym, type: :boolean, label: "Personalizar borda", default: false),
       Field.new(name: "#{key}border_style".to_sym, type: :select, label: "Estilo da borda", options: [["Sem borda", "none"], ["Sólida", "solid"], ["Tracejada", "dashed"]], default: "solid"),
       Field.new(name: "#{key}border_color".to_sym, type: :color, label: "Cor da borda", default: "#003344"),
       Field.new(name: "#{key}border_width".to_sym, type: :range, label: "Espessura (px)", options: [0, 12], default: 1),
       Field.new(name: "#{key}border_radius".to_sym, type: :range, label: "Cantos (px)", options: [0, 64], default: 8)]
    end

    # Typed controls are shared by blocks, cards, actions and individual text elements.
    def self.creative_fields(prefix, container: false)
      key = prefix.present? ? "#{prefix}_" : ""
      fields = [
        Field.new(name: "#{key}background_mode".to_sym, type: :select, label: "Tipo de fundo", options: [["Atual / herdado", "inherit"], ["Cor sólida", "solid"], ["Transparente", "transparent"], ["Gradiente", "gradient"]], default: "inherit"),
        Field.new(name: "#{key}background_opacity".to_sym, type: :range, label: "Opacidade do fundo (%)", options: [0, 100], default: 100),
        Field.new(name: "#{key}gradient_color".to_sym, type: :color, label: "Segunda cor do gradiente", default: "#b8972e"),
        Field.new(name: "#{key}gradient_kind".to_sym, type: :select, label: "Formato do gradiente", options: [["Linear", "linear"], ["Radial", "radial"]], default: "linear"),
        Field.new(name: "#{key}gradient_angle".to_sym, type: :range, label: "Direção do gradiente (°)", options: [0, 360], default: 135),
        Field.new(name: "#{key}text_opacity".to_sym, type: :range, label: "Opacidade do texto (%)", options: [0, 100], default: 100),
        Field.new(name: "#{key}text_gradient".to_sym, type: :boolean, label: "Gradiente no texto", default: false),
        Field.new(name: "#{key}text_gradient_color".to_sym, type: :color, label: "Segunda cor do texto", default: "#b8972e"),
        Field.new(name: "#{key}font_family".to_sym, type: :select, label: "Fonte", options: [["Atual / herdada", "inherit"], ["Sistema", "system"], ["Arial", "arial"], ["Georgia", "georgia"], ["Monoespaçada", "mono"]], default: "inherit"),
        Field.new(name: "#{key}font_size".to_sym, type: :range, label: "Tamanho (px · 0 = atual)", options: [0, 120], default: 0),
        Field.new(name: "#{key}font_weight".to_sym, type: :select, label: "Peso", options: [["Atual / herdado", "inherit"], ["Leve", "300"], ["Normal", "400"], ["Médio", "500"], ["Seminegrito", "600"], ["Negrito", "700"], ["Extranegrito", "800"]], default: "inherit"),
        Field.new(name: "#{key}font_style".to_sym, type: :select, label: "Estilo do texto", options: [["Atual / herdado", "inherit"], ["Normal", "normal"], ["Itálico", "italic"]], default: "inherit"),
        Field.new(name: "#{key}text_align".to_sym, type: :select, label: "Alinhamento do texto", options: [["Atual / herdado", "inherit"], *ALIGNS, ["Justificado", "justify"]], default: "inherit"),
        Field.new(name: "#{key}text_decoration".to_sym, type: :select, label: "Decoração", options: [["Atual / herdada", "inherit"], ["Nenhuma", "none"], ["Sublinhado", "underline"], ["Riscado", "line-through"]], default: "inherit"),
        Field.new(name: "#{key}text_transform".to_sym, type: :select, label: "Caixa do texto", options: [["Atual / herdada", "inherit"], ["Normal", "none"], ["MAIÚSCULAS", "uppercase"], ["minúsculas", "lowercase"], ["Iniciais Maiúsculas", "capitalize"]], default: "inherit"),
        Field.new(name: "#{key}line_height".to_sym, type: :range, label: "Entrelinhas (% · 0 = atual)", options: [0, 250], default: 0),
        Field.new(name: "#{key}letter_spacing".to_sym, type: :range, label: "Espaço entre letras (px)", options: [-3, 12], default: 0)
      ]
      if container
        fields.reject! { |field| field.name.to_s.match?(/text_gradient/) }
        fields += [Field.new(name: "#{key}backdrop_enabled".to_sym, type: :boolean, label: "Efeito de vidro", hint: "Filtra o que está atrás. Use um fundo parcialmente transparente.", default: false),
                   Field.new(name: "#{key}backdrop_blur".to_sym, type: :range, label: "Desfoque do fundo (px)", options: [0, 40], default: 12),
                   Field.new(name: "#{key}backdrop_saturation".to_sym, type: :range, label: "Saturação do fundo (%)", options: [0, 200], default: 100)]
      end
      fields
    end

    APPEARANCE_FIELDS = [
      Field.new(name: :block_custom_colors, type: :boolean, label: "Personalizar cores do bloco", default: false),
      Field.new(name: :block_background_color, type: :color, label: "Cor de fundo do bloco", default: "#ffffff"),
      Field.new(name: :block_text_color, type: :color, label: "Cor do texto do bloco", default: "#202b35"),
      Field.new(name: :content_width, type: :select, label: "Largura de leitura", options: [["Padrão do tema", "theme"], ["Editorial (900 px)", "reading"]], default: "theme"),
      Field.new(name: :anchor, type: :anchor, label: "Âncora da seção", default: "", hint: "Ex.: beneficios. Use #beneficios nos links desta página."),
      Field.new(name: :surface, type: :select, label: "Superfície", options: [["Padrão do bloco", "inherit"], ["Clara", "plain"], ["Suave", "soft"], ["Escura", "dark"], ["Cor da marca", "brand"]], default: "inherit"),
      Field.new(name: :density, type: :select, label: "Respiro", options: [["Padrão atual", "inherit"], ["Compacto", "compact"], ["Equilibrado", "balanced"], ["Amplo", "spacious"]], default: "inherit"),
      Field.new(name: :typography, type: :select, label: "Títulos", options: [["Padrão do tema", "inherit"], ["Sóbrio", "calm"], ["Editorial", "editorial"], ["Marcante", "bold"]], default: "inherit"),
      Field.new(name: :motion, type: :select, label: "Movimento", options: [["Sem animação", "none"], ["Entrada suave", "subtle"]], default: "none")
    ] .concat(border_fields("block") + creative_fields("block", container: true)).freeze
    EXTRAS = [
      Definition.new(key: "callout", label: "Destaque e chamada", icon: "info-square", description: "Painel com ícone, selo e até duas ações lado a lado.", fields: [
        Field.new(name: :heading, type: :string, label: "Título", limit: 200, default: ""),
        Field.new(name: :text, type: :rich, label: "Texto de apoio", limit: 3000, default: ""),
        Field.new(name: :badge_icon, type: :button_icon, label: "Ícone do selo", default: ""), Field.new(name: :badge, type: :string, label: "Selo", limit: 120, default: ""),
        Field.new(name: :icon, type: :button_icon, label: "Ícone", default: ""),
        Field.new(name: :align, type: :select, label: "Alinhamento", options: ALIGNS, default: "left"),
        Field.new(name: :button_icon, type: :button_icon, label: "Ícone da ação", default: ""), Field.new(name: :button_label, type: :string, label: "Ação principal", limit: 60, default: ""),
        Field.new(name: :button_url, type: :url, label: "Destino principal", default: ""),
        Field.new(name: :secondary_icon, type: :button_icon, label: "Ícone da segunda ação", default: ""), Field.new(name: :secondary_label, type: :string, label: "Segunda ação", limit: 60, default: ""),
        Field.new(name: :secondary_url, type: :url, label: "Segundo destino", default: "")
      ]),
      Definition.new(key: "faq", label: "Perguntas frequentes", icon: "question-circle", description: "Perguntas e respostas expansíveis, acessíveis pelo teclado.", fields: [
        Field.new(name: :heading, type: :string, label: "Título", default: "Perguntas frequentes"),
        Field.new(name: :filter_categories, type: :boolean, label: "Filtrar por categorias", default: false),
        Field.new(name: :searchable, type: :boolean, label: "Buscar nas perguntas", default: false),
        Field.new(name: :open_answers, type: :boolean, label: "Iniciar com respostas abertas", default: false),
        Field.new(name: :items, type: :items, label: "Perguntas", default: [], item_fields: [Field.new(name: :title, type: :string, label: "Pergunta", limit: 200), Field.new(name: :text, type: :rich, label: "Resposta", limit: 3000), Field.new(name: :group, type: :string, label: "Grupo", limit: 80), Field.new(name: :categories, type: :string, label: "Categorias (separadas por vírgula)", limit: 200), Field.new(name: :featured, type: :boolean, label: "Exibir como destaque", default: false), Field.new(name: :badge_icon, type: :button_icon, label: "Ícone do selo", default: ""), Field.new(name: :badge, type: :string, label: "Selo do destaque", limit: 120), Field.new(name: :icon, type: :icon, label: "Ícone do destaque")])
      ]),
      Definition.new(key: "navigation", label: "Navegação da página", icon: "signpost", description: "Links para as seções desta página. Informe #ancora no destino.", fields: [
        Field.new(name: :items, type: :items, label: "Links", default: [], item_fields: [Field.new(name: :title, type: :string, label: "Texto do link", limit: 80), Field.new(name: :url, type: :url, label: "Destino", placeholder: "#beneficios")])
      ])
    ].freeze

    ACTION_COLOR_FIELDS = %w[button secondary].flat_map do |prefix|
      [Field.new(name: "#{prefix}_custom_colors".to_sym, type: :boolean, label: "Personalizar cores #{prefix == 'button' ? 'da ação principal' : 'da segunda ação'}", default: false),
       Field.new(name: "#{prefix}_background_color".to_sym, type: :color, label: "Cor de fundo da ação", default: "#003344"),
       Field.new(name: "#{prefix}_text_color".to_sym, type: :color, label: "Cor do texto da ação", default: "#ffffff")]
    end.freeze

    def self.element_fields(definition)
      definition.fields.select { |field| %i[string text rich].include?(field.type) && !(definition.key == "button" && field.name == :label) && !field.name.to_s.match?(/(?:button|secondary)_label|url|anchor/) }.flat_map do |field|
        prefix = "element_#{field.name}"
        [Field.new(name: "#{prefix}_custom_colors".to_sym, type: :boolean, label: "Personalizar cores deste elemento", default: false),
         Field.new(name: "#{prefix}_background_color".to_sym, type: :color, label: "Fundo", default: "#ffffff"),
         Field.new(name: "#{prefix}_text_color".to_sym, type: :color, label: "Texto", default: "#003344")] + border_fields(prefix) + creative_fields(prefix)
      end
    end

    LABEL_FIELDS = [Field.new(name: :custom_colors, type: :boolean, label: "Personalizar cores", default: false), Field.new(name: :title, type: :string, label: "Texto", limit: 120),
                    Field.new(name: :background_color, type: :color, label: "Fundo", default: "#ffffff"),
                    Field.new(name: :text_color, type: :color, label: "Texto", default: "#003344")] + border_fields("") + creative_fields("")
    LABELS_FIELD = Field.new(name: :labels, type: :items, label: "Etiquetas", default: [], item_fields: LABEL_FIELDS)

    ALL = (RAW + [SECTION] + REPEATED + EXTRAS).map do |definition|
      definition.fields.each do |field|
        next unless field.type == :items
        field.item_fields += [Field.new(name: :row_key, type: :hidden)] unless field.item_fields.any? { |child| child.name == :row_key }
        field.item_fields += element_fields(Definition.new(fields: field.item_fields))
        field.item_fields += [Field.new(name: :custom_colors, type: :boolean, default: false), Field.new(name: :background_color, type: :color, label: "Fundo do card", default: "#ffffff"), Field.new(name: :text_color, type: :color, label: "Texto do card", default: "#003344")] + border_fields("") + creative_fields("", container: true)
      end
      fields = definition.fields + element_fields(definition)
      if definition.key.in?(%w[cover callout text])
        fields += [LABELS_FIELD] + element_fields(Definition.new(fields: [Field.new(name: :labels, type: :string)]))
      end
      fields += border_fields("") + creative_fields("") if definition.key == "button"
      fields += ACTION_COLOR_FIELDS + border_fields("button") + border_fields("secondary") + creative_fields("button") + creative_fields("secondary") if definition.key.in?(%w[cover callout])
      definition.fields = fields + [Field.new(name: :element_order, type: :element_order, default: "")] + [SPAN_FIELD, COLUMN_FIELD] + APPEARANCE_FIELDS + LAYOUT_FIELDS
      definition
    end.freeze

    BY_KEY = ALL.index_by(&:key).freeze

    def self.keys = BY_KEY.keys

    def self.fetch(key) = BY_KEY.fetch(key.to_s)

    def self.find(key) = BY_KEY[key.to_s]

    def self.options = ALL.map { |definition| [definition.label, definition.key] }
  end
end
