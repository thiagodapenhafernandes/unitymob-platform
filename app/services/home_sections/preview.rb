module HomeSections
  # O que a Home mostraria para uma seção (salva ou não): dados enxutos para a prévia ao vivo do formulário.
  # Reusa HomeSections::Showcase, a mesma regra da home pública.
  class Preview
    ITEMS = 3

    def self.call(section, tenant:)
      new(section, tenant).call
    end

    def initialize(section, tenant)
      @section = section
      @tenant = tenant
    end

    def call
      case section.content_kind
      when "blog" then blog
      when "cta" then cta
      else properties
      end.merge(title: section.title.to_s, subtitle: section.subtitle.to_s, active: section.active != false)
    end

    private

    attr_reader :section, :tenant

    def properties
      showcase = Showcase.new(section, habitations: tenant.habitations)
      development = section.development_content?
      if development
        ids = showcase.development_rows.map(&:first)
        manual = 0
        matching = tenant.habitations.empreendimentos_publicos.where.not(codigo: nil).count
      else
        split = showcase.property_split
        ids = split.values.flatten
        manual = split[:manual].size
        matching = section.apply_property_filters(tenant.habitations.active.without_developments).count
      end

      {
        kind: section.featured_videos? ? "property_videos" : (development ? "developments" : "properties"),
        count: ids.size + manual_video_items.size,
        limit: development ? Showcase::DEVELOPMENT_LIMIT : showcase.limit,
        manual: manual,
        matching: matching,
        cta_label: development ? "Ver Todos os Empreendimentos" : section.public_property_cta_label,
        corporate: section.corporate_showcase? && section.selected_property_ids.empty? ? tenant.habitations.active.home_corporate.limit(3).count : nil,
        items: (manual_video_items + items(ids.first(ITEMS))).first(ITEMS),
        warning: ids.empty? && manual_video_items.empty? ? "Nenhum imóvel atende a esses critérios: a seção não aparece na Home." : nil
      }
    end

    def manual_video_items
      return [] unless section.featured_videos?

      section.home_section_items.select(&:video_item?).select { |item| item.active != false }.filter_map do |item|
        next if item.title.blank?
        next if item.source_type == "external" && item.source_url.blank?
        next if item.source_type == "upload" && !item.video_file.attached?

        {
          title: item.title,
          price: item.price_label.presence || "Preço sob consulta",
          location: item.location.presence,
          badges: Array(item.badges).first(2),
          video: true
        }
      end
    end

    def blog
      articles = tenant.blog_articles.publicly_visible.recent.limit(3).to_a
      {
        kind: "blog",
        count: articles.size,
        limit: 3,
        items: articles.map { |article| { title: article.title, meta: article.published_at&.strftime("%d/%m/%Y") } },
        warning: articles.empty? ? "Não há artigos publicados: a seção não aparece na Home." : nil
      }
    end

    def cta
      { kind: "cta", count: 0, buttons: ["Fale Conosco", "Anuncie seu imóvel", "WhatsApp"], warning: nil, items: [] }
    end

    def items(ids)
      records = tenant.habitations.where(id: ids).includes(:address).index_by(&:id)
      ids.filter_map { |id| records[id] }.map do |habitation|
        {
          code: habitation.codigo.presence || habitation.id.to_s,
          title: habitation.display_title,
          price: price_label(habitation),
          location: [habitation.address&.bairro, habitation.address&.cidade].compact_blank.join(" · "),
          photo: habitation.image_urls.first
        }
      end
    end

    def price_label(habitation)
      sale = habitation.valor_venda_cents.to_i
      rent = habitation.valor_locacao_cents.to_i
      return format_money(sale) if sale.positive?

      rent.positive? ? "#{format_money(rent)}/mês" : "Sob consulta"
    end

    def format_money(cents)
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: "R$ ", separator: ",", delimiter: ".", precision: 0)
    end
  end
end
