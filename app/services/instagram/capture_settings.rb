module Instagram
  class CaptureSettings
    DEFAULT_NAME_PROMPT = "Olá! Como posso chamar você?".freeze
    DEFAULT_PHONE_PROMPT = "Qual é o seu telefone com DDD para nossa equipe continuar o atendimento?".freeze

    DEFAULT_EMAIL_PROMPT = "Se quiser, informe seu e-mail ou responda Pular.".freeze

    def initialize(page, tenant:)
      @key = "instagram_capture_#{page.instagram_id}"
      @tenant = tenant
    end

    def rules
      JSON.parse(Setting.tenant_get(@key, "{}", tenant: @tenant))
    end

    def save(campaign_id:, enabled:, name_prompt:, phone_prompt:, ask_email: false, email_prompt: "")
      @tenant.with_lock do
        updated = rules.merge(campaign_id => {
          "enabled" => enabled, "name_prompt" => name_prompt, "phone_prompt" => phone_prompt,
          "ask_email" => ask_email, "email_prompt" => email_prompt
        })
        Setting.set(@key, updated.to_json, tenant: @tenant)
      end
    end

    def self.prompts(rule)
      {
        "name_prompt" => rule["name_prompt"].presence || DEFAULT_NAME_PROMPT,
        "phone_prompt" => rule["phone_prompt"].presence || DEFAULT_PHONE_PROMPT,
        "email_prompt" => rule["email_prompt"].presence || DEFAULT_EMAIL_PROMPT
      }
    end
  end
end
