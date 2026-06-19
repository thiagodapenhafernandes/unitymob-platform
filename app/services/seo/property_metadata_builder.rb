module Seo
  class PropertyMetadataBuilder
    include Rails.application.routes.url_helpers

    DESCRIPTION_LIMIT = 155
    TITLE_LIMIT = 65

    def initialize(habitation)
      @habitation = habitation
    end

    def attributes
      {
        canonical_key: "property:#{identifier}",
        page_name: "imovel:#{identifier}",
        page_type: page_type,
        canonical_path: habitation_path(@habitation),
        meta_title: meta_title,
        meta_description: meta_description,
        meta_keywords: meta_keywords,
        og_title: meta_title,
        og_description: meta_description
      }
    end

    private

    def identifier
      @habitation.codigo.presence || @habitation.id
    end

    def page_type
      @habitation.empreendimento? ? "development_show" : "property_show"
    end

    def meta_title
      base = @habitation.meta_title.presence || @habitation.display_title.presence || @habitation.titulo_anuncio.presence || "Imovel"
      title = base.to_s.squish
      return title.truncate(TITLE_LIMIT, separator: " ", omission: "") if title.match?(/\|\s*#{Regexp.escape(site_name)}\z/i)

      suffix = " | #{site_name}"
      max_base_length = [TITLE_LIMIT - suffix.length, 20].max
      "#{title.truncate(max_base_length, separator: " ", omission: "...")}#{suffix}"
    end

    def meta_description
      source = plain_text(@habitation.meta_description).presence ||
               @habitation.display_description_plain_text.presence ||
               @habitation.seo_description.presence ||
               fallback_description

      source.to_s.squish.truncate(DESCRIPTION_LIMIT, separator: " ", omission: "")
    end

    def meta_keywords
      [
        @habitation.categoria,
        @habitation.tipo_transacao,
        @habitation.cidade,
        @habitation.bairro,
        @habitation.nome_empreendimento,
        site_name,
        "imobiliaria"
      ].compact_blank.map(&:to_s).map(&:squish).uniq.join(", ")
    end

    def fallback_description
      parts = []
      parts << @habitation.display_title
      parts << [@habitation.bairro, @habitation.cidade].compact_blank.join(", ")
      parts << "#{@habitation.dormitorios_qtd} dormitorios" if @habitation.dormitorios_qtd.to_i.positive?
      parts << "#{@habitation.suites_qtd} suites" if @habitation.suites_qtd.to_i.positive?
      parts << "#{@habitation.vagas_qtd} vagas" if @habitation.vagas_qtd.to_i.positive?
      parts << "Confira fotos, detalhes e disponibilidade."
      parts.compact_blank.join(". ")
    end

    def plain_text(value)
      return if value.blank?
      return value.to_plain_text if value.respond_to?(:to_plain_text)

      ActionController::Base.helpers.strip_tags(value.to_s)
    end

    def site_name
      LayoutSetting.instance.site_name.presence || "Unitymob"
    rescue StandardError
      "Unitymob"
    end
  end
end
