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
        page_name: page_name,
        page_type: page_type,
        canonical_path: canonical_path,
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

    def page_name
      @habitation.empreendimento? ? "empreendimento:#{identifier}" : "imovel:#{identifier}"
    end

    def meta_title
      base = @habitation.empreendimento? ? development_title_source : property_title_source
      title = base.to_s.squish
      return title.truncate(TITLE_LIMIT, separator: " ", omission: "") if title.match?(/\|\s*#{Regexp.escape(site_name)}\z/i)

      append_site_suffix(title)
    end

    def property_title_source
      @habitation.meta_title.presence || @habitation.display_title.presence || @habitation.titulo_anuncio.presence || "Imovel"
    end

    def development_title_source
      return @habitation.meta_title if @habitation.meta_title.present?

      name = development_name
      location_candidates = [
        [@habitation.public_neighborhood, @habitation.cidade].compact_blank.join(", "),
        @habitation.cidade
      ].compact_blank.uniq

      location_candidates.each do |location|
        candidate = "#{name} em #{location}"
        return candidate if fits_with_site_suffix?(candidate)
      end

      name
    end

    def append_site_suffix(title)
      title = title.to_s.squish

      suffix = " | #{site_name}"
      max_base_length = [TITLE_LIMIT - suffix.length, 20].max
      "#{title.truncate(max_base_length, separator: " ", omission: "...")}#{suffix}"
    end

    def fits_with_site_suffix?(title)
      "#{title} | #{site_name}".length <= TITLE_LIMIT
    end

    def meta_description
      source = plain_text(@habitation.meta_description).presence
      source ||= @habitation.empreendimento? ? development_description : property_description

      source.to_s.squish.truncate(DESCRIPTION_LIMIT, separator: " ", omission: "")
    end

    def property_description
      @habitation.display_description_plain_text.presence ||
        @habitation.seo_description.presence ||
        fallback_description
    end

    def development_description
      parts = []
      parts << "Conheça o #{development_name}#{development_location_phrase}."
      parts << "Empreendimento #{constructor_phrase}." if constructor_phrase.present?
      parts << "Unidades disponíveis com #{development_unit_summary}." if development_unit_summary.present?
      parts << "Veja fotos, endereço, detalhes e fale com a #{site_name}."
      parts.compact_blank.join(" ")
    end

    def meta_keywords
      [
        @habitation.categoria,
        @habitation.tipo_transacao,
        @habitation.cidade,
        @habitation.public_neighborhood,
        development_keyword,
        development_constructor_keyword,
        development_city_keyword,
        site_name,
        "imobiliaria"
      ].compact_blank.map(&:to_s).map(&:squish).uniq.join(", ")
    end

    def fallback_description
      parts = []
      parts << @habitation.display_title
      parts << [@habitation.public_neighborhood, @habitation.cidade].compact_blank.join(", ")
      parts << "#{@habitation.dormitorios_qtd} dormitorios" if @habitation.dormitorios_qtd.to_i.positive?
      parts << "#{@habitation.suites_qtd} suites" if @habitation.suites_qtd.to_i.positive?
      parts << "#{@habitation.vagas_qtd} vagas" if @habitation.vagas_qtd.to_i.positive?
      parts << "Confira fotos, detalhes e disponibilidade."
      parts.compact_blank.join(". ")
    end

    def canonical_path
      return empreendimento_details_path(@habitation) if @habitation.empreendimento?

      habitation_path(@habitation)
    end

    def development_keyword
      @habitation.nome_empreendimento if @habitation.empreendimento?
    end

    def development_constructor_keyword
      @habitation.constructor_name if @habitation.empreendimento?
    end

    def development_city_keyword
      return unless @habitation.empreendimento? && @habitation.cidade.present?

      "empreendimento #{@habitation.cidade}"
    end

    def development_name
      @habitation.nome_empreendimento.presence ||
        @habitation.titulo_anuncio.presence ||
        @habitation.display_title.presence ||
        "Empreendimento"
    end

    def development_location_phrase
      location = [@habitation.public_neighborhood, @habitation.cidade].compact_blank.join(", ")
      return "" if location.blank?

      " em #{location}"
    end

    def constructor_phrase
      @habitation.constructor_name.presence
    end

    def development_unit_summary
      @development_unit_summary ||= begin
        parts = []
        parts << "#{range_text(area_values)} m² de área privativa" if area_values.any?
        parts << "#{range_text(suite_values)} suítes" if suite_values.any?
        parts << "#{range_text(bedroom_values)} dormitórios" if suite_values.blank? && bedroom_values.any?
        parts << "#{range_text(parking_values)} vagas" if parking_values.any?
        parts.join(", ").presence
      end
    end

    def area_values
      @area_values ||= development_units.filter_map(&:public_area_m2).map(&:to_f).select(&:positive?)
    end

    def suite_values
      @suite_values ||= development_units.map(&:suites_qtd).map(&:to_i).select(&:positive?)
    end

    def bedroom_values
      @bedroom_values ||= development_units.map(&:dormitorios_qtd).map(&:to_i).select(&:positive?)
    end

    def parking_values
      @parking_values ||= development_units.map(&:vagas_qtd).map(&:to_i).select(&:positive?)
    end

    def development_units
      @development_units ||= @habitation.empreendimento? ? @habitation.development_units.to_a : []
    end

    def range_text(values)
      normalized = values.map { |value| value.to_f.round }.uniq.sort
      return if normalized.blank?

      normalized.one? ? normalized.first.to_s : "#{normalized.first} a #{normalized.last}"
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
