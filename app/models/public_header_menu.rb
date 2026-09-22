# Menu do topo do site público. O que a conta grava (HomeSetting#header_menu) é só a
# personalização: ordem, visibilidade, rótulo e links próprios. Os itens do sistema vivem
# aqui, então uma página nova do site aparece sem migration e um menu vazio equivale ao
# desenho original.
class PublicHeaderMenu
  ROUTES = Rails.application.routes.url_helpers
  MAX_CUSTOM_ITEMS = 12
  LABEL_LIMIT = 40
  URL_FORMAT = %r{\A(/[^\s]*|https?://[^\s]+|mailto:[^\s]+|tel:[^\s]+)\z}i

  # bar: aparece na barra do desktop (todos os visíveis entram no menu suspenso e no celular).
  # requires: item só existe quando a conta tem o dado (blog, canal do YouTube).
  SYSTEM_ITEMS = {
    "home"         => { label: "Home", path: -> { ROUTES.root_path } },
    "comprar"      => { label: "Comprar", bar: true, path: -> { ROUTES.habitations_path(transaction_type: "venda") }, active: ->(c) { c.buying? } },
    "alugar"       => { label: "Alugar", bar: true, path: -> { ROUTES.habitations_path(transaction_type: "aluguel") }, active: ->(c) { c.renting? } },
    "anunciar"     => { label: "Anunciar", bar: true, path: -> { ROUTES.contato_path } },
    "empreendimentos" => { label: "Empreendimentos", bar: true, path: -> { ROUTES.empreendimentos_path }, active: ->(c) { c.developments? } },
    "lancamentos"  => { label: "Lançamentos", bar: true, path: -> { ROUTES.habitations_path(characteristics: ["lancamento"]) }, active: ->(c) { c.launches? } },
    "blog"         => { label: "Blog", bar: true, requires: :blog },
    "favoritos"    => { label: "Favoritos", bar: true, icon: "bookmark-heart", path: -> { ROUTES.favorite_habitations_path } },
    "parceria"     => { label: "Parceria", path: -> { ROUTES.parcerias_path } },
    "corretor"     => { label: "Fale com um corretor", path: -> { ROUTES.brokers_path } },
    "galpoes"      => { label: "Galpões", path: -> { ROUTES.corporativos_path } },
    "financiamento" => { label: "Simule um financiamento", path: -> { ROUTES.simulador_path } },
    "trabalhe"     => { label: "Trabalhe conosco", path: -> { ROUTES.trabalhe_conosco_path } },
    "sobre"        => { label: "Sobre nós", path: -> { ROUTES.sobre_path } },
    "youtube"      => { label: "YouTube", requires: :youtube },
    "links_uteis"  => { label: "Links Úteis", path: -> { ROUTES.links_uteis_path } },
    "contato"      => { label: "Contato", path: -> { ROUTES.contato_path } }
  }.freeze

  DEFAULT_CTA_LABEL = "Fale Conosco".freeze

  Entry = Struct.new(:key, :label, :default_label, :url, :visible, :bar, :new_tab, :custom, :icon, :active, :available, keyword_init: true) do
    alias_method :custom?, :custom
    alias_method :visible?, :visible
    alias_method :bar?, :bar
    alias_method :active?, :active
    alias_method :available?, :available
  end

  # Onde o visitante está, para marcar o item ativo.
  Context = Struct.new(:controller_name, :params, keyword_init: true) do
    def habitations? = controller_name == "habitations"
    def transaction = params[:transaction_type].to_s.downcase
    def buying? = habitations? && transaction == "venda"
    def renting? = habitations? && %w[aluguel locacao locação].include?(transaction)
    def developments? = controller_name == "empreendimentos" || (habitations? && Array(params[:category]).map(&:to_s).include?("Empreendimento"))
    def launches? = habitations? && Array(params[:characteristics]).map(&:to_s).include?("lancamento")
  end

  # Lista completa (sistema + próprios) na ordem gravada; itens de sistema novos entram no fim.
  def self.entries(saved, blog_url: nil, youtube_url: nil, context: nil)
    saved = Array(saved).select { |item| item.is_a?(Hash) }.map { |item| item.stringify_keys }
    ordered = saved.select { |item| item["key"].to_s.in?(SYSTEM_ITEMS.keys) || custom_item?(item) }
    missing = SYSTEM_ITEMS.keys - ordered.map { |item| item["key"] }
    ordered += missing.map { |key| { "key" => key } }

    ordered.filter_map do |item|
      custom_item?(item) ? custom_entry(item) : system_entry(item, blog_url:, youtube_url:, context:)
    end.uniq(&:key)
  end

  # Só o que o visitante enxerga.
  def self.visible(saved, **options)
    entries(saved, **options).select { |entry| entry.visible? && entry.available? && entry.url.present? }
  end

  # Sanitiza o que vem do formulário (índice => campos), preservando a ordem por "position".
  def self.normalize(raw)
    rows = raw.respond_to?(:values) ? raw.values : Array(raw)
    rows = rows.select { |row| row.respond_to?(:to_h) }.map { |row| row.to_h.stringify_keys }
    rows = rows.reject { |row| ActiveModel::Type::Boolean.new.cast(row["_destroy"]) }
    rows = rows.sort_by.with_index { |row, index| [row["position"].to_i.nonzero? || (index + 1), index] }

    custom_seen = 0
    rows.filter_map do |row|
      key = row["key"].to_s
      visible = ActiveModel::Type::Boolean.new.cast(row["visible"]) != false
      bar = ActiveModel::Type::Boolean.new.cast(row["bar"]) || false
      label = row["label"].to_s.squish.first(LABEL_LIMIT).presence

      if SYSTEM_ITEMS.key?(key)
        { "key" => key, "label" => (label unless label == SYSTEM_ITEMS[key][:label]), "visible" => visible, "bar" => bar }.compact
      elsif row["url"].to_s.strip.match?(URL_FORMAT) && label && (custom_seen += 1) <= MAX_CUSTOM_ITEMS
        { "key" => key.presence&.first(40) || "custom-#{SecureRandom.hex(3)}", "custom" => true, "label" => label,
          "url" => row["url"].to_s.strip, "visible" => visible, "bar" => bar,
          "new_tab" => ActiveModel::Type::Boolean.new.cast(row["new_tab"]) || false }
      end
    end
  end

  def self.custom_item?(item)
    item["custom"] == true && item["url"].to_s.match?(URL_FORMAT) && item["label"].present?
  end

  def self.custom_entry(item)
    Entry.new(key: item["key"], label: item["label"], default_label: item["label"], url: item["url"], visible: item["visible"] != false,
              bar: item["bar"] == true, new_tab: item["new_tab"] == true, custom: true, available: true, active: false)
  end

  def self.system_entry(item, blog_url:, youtube_url:, context:)
    key = item["key"]
    definition = SYSTEM_ITEMS.fetch(key)
    url = case definition[:requires]
          when :blog then blog_url
          when :youtube then youtube_url
          else definition[:path].call
          end

    Entry.new(key: key, label: item["label"].presence || definition[:label], default_label: definition[:label], url: url,
              visible: item.fetch("visible", true) != false, bar: item.fetch("bar", definition[:bar] == true) == true,
              new_tab: definition[:requires] == :youtube || (definition[:requires] == :blog && blog_url.to_s.start_with?("http")),
              custom: false, icon: definition[:icon], active: context ? definition[:active]&.call(context) == true : false,
              available: definition[:requires].nil? || url.present?)
  end
  private_class_method :custom_item?, :custom_entry, :system_entry
end
