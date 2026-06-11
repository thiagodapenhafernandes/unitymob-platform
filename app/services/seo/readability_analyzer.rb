module Seo
  class ReadabilityAnalyzer
    Result = Struct.new(:score, :label, :checks, keyword_init: true)

    def initialize(seo_setting)
      @seo = seo_setting
      @text = [
        seo_setting.meta_title,
        seo_setting.meta_description,
        seo_setting.intro_text,
        seo_setting.og_description
      ].join(" ").squish
    end

    def call
      checks = {
        sentence_length: sentence_length_check,
        paragraph_size: paragraph_size_check,
        passive_density: passive_density_check,
        transition_words: transition_words_check,
        keyword_naturalness: keyword_naturalness_check
      }
      score = (checks.values.sum { |item| item[:points] }.to_f / checks.size).round

      Result.new(score: score, label: label_for(score), checks: checks)
    end

    private

    attr_reader :seo, :text

    def sentence_length_check
      sentences = text.split(/[.!?]+/).map(&:squish).reject(&:blank?)
      average = sentences.any? ? (sentences.sum { |sentence| words(sentence).size }.to_f / sentences.size).round(1) : 0
      ok = average.positive? && average <= 24
      build_check(ok, ok ? "Frases em bom ritmo." : "Reduza frases longas para facilitar leitura.", average)
    end

    def paragraph_size_check
      paragraphs = seo.intro_text.to_s.split(/\n{2,}/).map(&:squish).reject(&:blank?)
      largest = paragraphs.map { |paragraph| words(paragraph).size }.max.to_i
      ok = largest.zero? || largest <= 90
      build_check(ok, ok ? "Parágrafos escaneáveis." : "Quebre blocos grandes em parágrafos menores.", largest)
    end

    def passive_density_check
      total = words(text).size
      passive_hits = text.scan(/\b(foi|foram|será|serão|sendo|sido)\b/i).size
      density = total.positive? ? ((passive_hits.to_f / total) * 100).round(1) : 0
      ok = density <= 2.5
      build_check(ok, ok ? "Voz passiva sob controle." : "Reduza construções passivas quando possível.", "#{density}%")
    end

    def transition_words_check
      transitions = %w[além disso portanto assim também enquanto porque caso porém ainda dessa forma com isso]
      hits = transitions.count { |word| text.downcase.include?(word) }
      ok = hits >= 2 || words(text).size < 80
      build_check(ok, ok ? "Boa fluidez entre ideias." : "Inclua conectores para melhorar fluidez.", hits)
    end

    def keyword_naturalness_check
      keywords = seo.focus_keywords.map(&:keyword)
      return build_check(true, "Sem keyword foco obrigatória.", 0) if keywords.blank?

      content = text.downcase
      present = keywords.count { |keyword| content.include?(keyword.downcase) }
      ok = present >= [keywords.size, 2].min
      build_check(ok, ok ? "Keywords aparecem naturalmente no texto." : "Inclua as keywords foco em título/descrição de forma natural.", present)
    end

    def build_check(ok, message, metric)
      { ok: ok, points: ok ? 100 : 45, message: message, metric: metric }
    end

    def label_for(score)
      case score
      when 85..100 then "Ótima"
      when 70..84 then "Boa"
      when 50..69 then "Atenção"
      else "Fraca"
      end
    end

    def words(value)
      value.to_s.scan(/\S+/)
    end
  end
end
