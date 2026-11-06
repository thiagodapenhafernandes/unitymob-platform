module Instagram
  class CaptureSettings
    DEFAULT_NAME_PROMPT = "Olá! Como posso chamar você?".freeze
    DEFAULT_PHONE_PROMPT = "Qual é o seu telefone com DDD para nossa equipe continuar o atendimento?".freeze

    DEFAULT_EMAIL_PROMPT = "Se quiser, informe seu e-mail ou responda Pular.".freeze

    DEFAULT_THANK_YOU = "Obrigado, {primeiro_nome}! Já tenho seus dados. Você tem algum imóvel em mente ou quer ajuda para encontrar opções?"
    DEFAULT_AI_INSTRUCTIONS = "Atenda em português do Brasil, com cordialidade e mensagens curtas. Faça uma pergunta por vez. Considere o contexto da conversa e esclareça o que a pessoa procura, como cidade, bairro e faixa de preço."
    AI_INSTRUCTIONS_LIMIT = 3000

    def initialize(page, tenant:)
      @key = "instagram_capture_#{page.instagram_id}"
      @tenant = tenant
    end

    def rules
      JSON.parse(Setting.tenant_get(@key, "{}", tenant: @tenant))
    end

    def save(campaign_id:, enabled:, name_prompt:, phone_prompt:, ask_email: false, email_prompt: "", create_only: false)
      save_many(campaign_ids: [campaign_id], create_only: create_only, rule: {
          "enabled" => enabled, "name_prompt" => name_prompt, "phone_prompt" => phone_prompt,
          "ask_email" => ask_email, "email_prompt" => email_prompt
      })
    end

    def save_many(campaign_ids:, create_only:, rule:)
      @tenant.with_lock do
        existing = rules
        next false if create_only && campaign_ids.any? { |id| existing.key?(id) }

        Setting.set(@key, existing.merge(campaign_ids.index_with { rule }).to_json, tenant: @tenant)
      end
    end

    def self.prompts(rule)
      {
        "name_prompt" => rule["name_prompt"].presence || DEFAULT_NAME_PROMPT,
        "phone_prompt" => rule["phone_prompt"].presence || DEFAULT_PHONE_PROMPT,
        "email_prompt" => rule["email_prompt"].presence || DEFAULT_EMAIL_PROMPT,
        "thank_you_prompt" => rule["thank_you_prompt"].presence || DEFAULT_THANK_YOU
      }
    end
  end
end
