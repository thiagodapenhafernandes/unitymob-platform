module Dashboard
  class AiDiagnosis
    FEATURE = "dashboard_weekly_diagnosis".freeze
    ENABLED_SETTING = "openai_dashboard_diagnosis_enabled".freeze
    WEEKLY_REQUEST_LIMIT_SETTING = "openai_dashboard_diagnosis_weekly_request_limit".freeze
    MONTHLY_BUDGET_CENTS_SETTING = "openai_dashboard_diagnosis_monthly_budget_cents".freeze
    DEFAULT_WEEKLY_REQUEST_LIMIT = 1
    DEFAULT_MONTHLY_BUDGET_CENTS = 1_000
    CACHE_SETTING_PREFIX = "openai_dashboard_diagnosis_cache".freeze
    INPUT_TOKEN_PRICE_MICROCENTS = 15
    OUTPUT_TOKEN_PRICE_MICROCENTS = 60

    def self.enabled?(tenant:)
      ActiveModel::Type::Boolean.new.cast(Setting.tenant_get(ENABLED_SETTING, "false", tenant: tenant))
    end

    def self.weekly_request_limit(tenant:)
      Setting.tenant_get(WEEKLY_REQUEST_LIMIT_SETTING, DEFAULT_WEEKLY_REQUEST_LIMIT.to_s, tenant: tenant).to_i.clamp(0, 10)
    end

    def self.monthly_budget_cents(tenant:)
      Setting.tenant_get(MONTHLY_BUDGET_CENTS_SETTING, DEFAULT_MONTHLY_BUDGET_CENTS.to_s, tenant: tenant).to_i.clamp(0, 100_000)
    end

    def initialize(tenant:, period:, metrics:, admin_user: nil)
      @tenant = tenant
      @period = period.to_i
      @metrics = metrics.with_indifferent_access
      @admin_user = admin_user
    end

    def call
      deterministic = deterministic_diagnosis
      return deterministic.merge(source: "deterministic", ai_enabled: false, limit_status: limit_status) unless ai_available?

      cached = cached_diagnosis
      return deterministic.merge(cached).merge(source: "openai_cache", ai_enabled: true, limit_status: limit_status) if cached.present?

      return deterministic.merge(source: "deterministic", ai_enabled: true, limit_status: limit_status) unless within_limits?

      parsed = request_diagnosis
      save_cache!(parsed)
      deterministic.merge(parsed).merge(source: "openai", ai_enabled: true, limit_status: limit_status)
    rescue => e
      Rails.logger.warn("[dashboard ai diagnosis] #{e.class}: #{e.message}")
      deterministic_diagnosis.merge(source: "deterministic", ai_enabled: ai_enabled?, error: e.message, limit_status: limit_status)
    end

    private

    attr_reader :tenant, :period, :metrics, :admin_user

    def ai_available?
      ai_enabled? && Ai::PropertyContentService.connected?(tenant: tenant)
    end

    def ai_enabled?
      self.class.enabled?(tenant: tenant)
    end

    def within_limits?
      limit_status[:weekly_remaining].positive? && limit_status[:monthly_budget_remaining_cents].positive?
    end

    def limit_status
      @limit_status ||= begin
        weekly_limit = self.class.weekly_request_limit(tenant: tenant)
        monthly_budget = self.class.monthly_budget_cents(tenant: tenant)
        weekly_used = OpenAiUsageEvent.requests_count(tenant: tenant, feature: FEATURE, since: Time.current.beginning_of_week)
        monthly_cost = OpenAiUsageEvent.estimated_cost_cents(tenant: tenant, feature: FEATURE, since: Time.current.beginning_of_month)

        {
          weekly_limit: weekly_limit,
          weekly_used: weekly_used,
          weekly_remaining: [weekly_limit - weekly_used, 0].max,
          monthly_budget_cents: monthly_budget,
          monthly_cost_cents: monthly_cost,
          monthly_budget_remaining_cents: [monthly_budget - monthly_cost, 0].max
        }
      end
    end

    def deterministic_diagnosis
      recommendations = deterministic_recommendations
      {
        title: "Diagnóstico da semana",
        summary: deterministic_summary(recommendations),
        recommendations: recommendations,
        rationale: deterministic_rationale
      }
    end

    def deterministic_summary(recommendations)
      return "Operação sem alerta crítico no período; mantenha a rotina de acompanhamento dos principais indicadores." if recommendations.blank?

      "Principais frentes: #{recommendations.first(3).map { |item| item[:title] }.to_sentence.downcase}."
    end

    def deterministic_recommendations
      rows = []
      add_recommendation(rows, "Atender leads sem primeiro contato", metrics[:no_first_contact_leads], "Priorize leads sem atividade registrada antes de revisar novas origens.", "red")
      add_recommendation(rows, "Responder conversas de WhatsApp pendentes", metrics[:pending_whatsapp_conversations], "Conversa aberta sem retorno tende a perder intenção rapidamente.", "red")
      add_recommendation(rows, "Revisar imóveis com interesse sem evolução", metrics[:property_low_progress_count], "Há procura, mas ainda não existe visita/proposta associada.", "amber")
      add_recommendation(rows, "Corrigir desperdício de mídia paga", metrics[:lost_money_count], "Leads pagos, canais fracos ou campanhas caras precisam de revisão.", "amber")
      add_recommendation(rows, "Reduzir gargalos do funil", metrics[:stage_bottleneck_count], "Etapas com tempo alto, perda ou reabertura merecem ação do gestor.", "amber")
      rows.sort_by { |item| [item[:tone] == "red" ? 0 : 1, -item[:value].to_i] }.first(5)
    end

    def add_recommendation(rows, title, value, detail, tone)
      value = value.to_i
      return unless value.positive?

      rows << { title: title, detail: detail, value: value, tone: tone }
    end

    def deterministic_rationale
      [
        "#{metrics[:leads_total].to_i} lead(s) no período analisado",
        "#{metrics[:site_visits].to_i} visita(s) públicas rastreadas",
        "#{metrics[:lost_money_count].to_i} sinal(is) de dinheiro perdido",
        "#{metrics[:stage_bottleneck_count].to_i} gargalo(s) de funil"
      ]
    end

    def request_diagnosis
      response = OpenAi::Client.new(api_key: Ai::PropertyContentService.api_key(tenant: tenant)).create_response(
        openai_payload,
        fallback_model: OpenAi::ModelCatalog.fallback_response_model(Ai::PropertyContentService.resolved_model(tenant: tenant))
      )
      parsed = JSON.parse(extract_text(response))
        .with_indifferent_access
        .slice(:title, :summary, :recommendations, :rationale)
        .deep_symbolize_keys
      record_usage!(response, status: "succeeded")
      parsed
    rescue => e
      record_usage!({}, status: "failed", error: e.message)
      raise
    end

    def openai_payload
      {
        model: Ai::PropertyContentService.resolved_model(tenant: tenant),
        instructions: system_instructions,
        input: metrics.to_json,
        text: {
          format: {
            type: "json_schema",
            name: "dashboard_weekly_diagnosis",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              required: %w[title summary recommendations rationale],
              properties: {
                title: { type: "string" },
                summary: { type: "string" },
                recommendations: {
                  type: "array",
                  items: {
                    type: "object",
                    additionalProperties: false,
                    required: %w[title detail value tone],
                    properties: {
                      title: { type: "string" },
                      detail: { type: "string" },
                      value: { type: "integer" },
                      tone: { type: "string", enum: %w[red amber blue green] }
                    }
                  }
                },
                rationale: { type: "array", items: { type: "string" } }
              }
            }
          }
        }
      }
    end

    def system_instructions
      <<~TEXT
        Você é um analista operacional de uma imobiliária.
        Gere um diagnóstico semanal objetivo, em português do Brasil, para gestores comerciais.
        Não invente dados: use somente os números do JSON.
        Priorize dinheiro perdido, SLA, WhatsApp, funil e site público.
        Recomendações devem ser acionáveis, curtas e sem prometer resultado.
      TEXT
    end

    def cached_diagnosis
      raw = Setting.tenant_get(cache_key, nil, tenant: tenant)
      return nil if raw.blank?

      JSON.parse(raw).with_indifferent_access
    rescue JSON::ParserError
      nil
    end

    def save_cache!(payload)
      Setting.set(cache_key, payload.to_json, "Cache semanal do diagnóstico do BI", tenant: tenant)
    end

    def cache_key
      "#{CACHE_SETTING_PREFIX}_#{Time.current.strftime("%G_%V")}_#{period}"
    end

    def record_usage!(response, status:, error: nil)
      usage = response.to_h["usage"].to_h
      input_tokens = usage["input_tokens"].to_i
      output_tokens = usage["output_tokens"].to_i
      OpenAiUsageEvent.create!(
        tenant: tenant,
        admin_user: admin_user,
        feature: FEATURE,
        model: Ai::PropertyContentService.resolved_model(tenant: tenant),
        status: status,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        estimated_cost_cents: estimated_cost_cents(input_tokens, output_tokens),
        metadata: { period: period, error: error }.compact
      )
    end

    def estimated_cost_cents(input_tokens, output_tokens)
      microcents = (input_tokens.to_i * INPUT_TOKEN_PRICE_MICROCENTS) + (output_tokens.to_i * OUTPUT_TOKEN_PRICE_MICROCENTS)
      (microcents / 1_000_000.0).ceil
    end

    def extract_text(response)
      return response["output_text"] if response["output_text"].present?

      Array(response["output"]).flat_map { |item| Array(item["content"]) }.map { |content| content["text"] }.compact.join("\n")
    end
  end
end
