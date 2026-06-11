module Seo
  class Analyzer
    def initialize(seo_setting)
      @seo = seo_setting
    end

    def score
      points = 0
      points += title_score
      points += description_score
      points += 10 if @seo.canonical_path.present? || @seo.canonical_url.present?
      points += 10 if @seo.robots_index?
      points += 10 if @seo.og_title.present? || @seo.meta_title.present?
      points += 10 if @seo.og_description.present? || @seo.meta_description.present?
      points += 10 if @seo.meta_keywords.present?
      points += 10 if @seo.intro_text.present? || !listing_page?
      points.clamp(0, 100)
    end

    def insights
      notes = []
      title = @seo.meta_title.to_s
      description = @seo.meta_description.to_s

      notes << "Meta title ausente." if title.blank?
      notes << "Meta title muito curto; tente chegar perto de 45 a 60 caracteres." if title.present? && title.length < 35
      notes << "Meta title longo; idealmente mantenha abaixo de 60 caracteres." if title.length > 65
      notes << "Meta description ausente." if description.blank?
      notes << "Meta description curta; busque algo entre 120 e 160 caracteres." if description.present? && description.length < 110
      notes << "Meta description longa; pode ser cortada nos buscadores." if description.length > 170
      notes << "Canonical ausente." if @seo.canonical_path.blank? && @seo.canonical_url.blank?
      notes << "Página marcada como noindex." unless @seo.robots_index?
      notes << "Palavras-chave ausentes para orientar cluster semântico." if @seo.meta_keywords.blank?
      notes << "Texto introdutório ausente; listagens estratégicas precisam de conteúdo único." if listing_page? && @seo.intro_text.blank?
      notes.presence || ["SEO técnico em bom estado para indexação."]
    end

    private

    def title_score
      title = @seo.meta_title.to_s
      return 0 if title.blank?
      return 20 if title.length.between?(35, 65)
      10
    end

    def description_score
      description = @seo.meta_description.to_s
      return 0 if description.blank?
      return 30 if description.length.between?(110, 170)
      15
    end

    def listing_page?
      @seo.page_type.to_s.in?(%w[property_listing property_landing developments_index development_landing])
    end
  end
end
