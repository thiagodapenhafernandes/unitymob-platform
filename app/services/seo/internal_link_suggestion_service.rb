module Seo
  class InternalLinkSuggestionService
    Suggestion = Struct.new(:title, :url, :reason, :score, keyword_init: true)

    def initialize(seo_setting, limit: 6)
      @seo = seo_setting
      @limit = limit
      @keywords = seo_setting.focus_keywords.map(&:keyword)
      @text = [
        seo_setting.meta_title,
        seo_setting.meta_description,
        seo_setting.meta_keywords,
        seo_setting.intro_text
      ].join(" ").downcase
    end

    def call
      suggestions = []
      suggestions.concat(seo_setting_suggestions)
      suggestions.concat(property_suggestions)
      suggestions.sort_by { |suggestion| -suggestion.score }.uniq(&:url).first(@limit)
    end

    private

    attr_reader :seo, :keywords, :text

    def seo_setting_suggestions
      SeoSetting.where(active: true, apply_to_public: true, robots_index: true)
                .where.not(id: seo.id)
                .order(access_count: :desc, seo_score: :desc)
                .limit(40)
                .filter_map do |candidate|
        score = candidate_score(candidate.display_name, candidate.meta_description, candidate.meta_keywords)
        next if score <= 0

        Suggestion.new(
          title: candidate.display_name,
          url: candidate.sanitized_canonical_path,
          reason: reason_for(candidate),
          score: score
        )
      end
    end

    def property_suggestions
      Habitation.active.without_developments.limit(30).filter_map do |habitation|
        score = candidate_score(habitation.display_title, habitation.bairro, habitation.cidade)
        next if score <= 0

        Suggestion.new(
          title: habitation.display_title,
          url: Rails.application.routes.url_helpers.habitation_path(habitation),
          reason: "Imóvel relacionado por localização/tipo",
          score: score
        )
      rescue
        nil
      end
    end

    def candidate_score(*values)
      candidate_text = values.compact.join(" ").downcase
      score = 0
      keywords.each { |keyword| score += 20 if candidate_text.include?(keyword.downcase) }
      text.scan(/\w{4,}/).uniq.first(80).each { |term| score += 1 if candidate_text.include?(term) }
      score
    end

    def reason_for(candidate)
      if candidate.page_type.to_s.include?("landing")
        "Landing estratégica relacionada"
      elsif candidate.page_type.to_s.include?("listing")
        "Listagem relacionada por intenção de busca"
      else
        "Página pública relacionada"
      end
    end
  end
end
