module Instagram
  class CaptureSettings
    DEFAULT_NAME_PROMPT = "Olá! Vou te ajudar com o imóvel 😊 Como posso te chamar?".freeze
    DEFAULT_PHONE_PROMPT = "Para consultar o imóvel ou encaminhar ao corretor, preciso do seu telefone com DDD. Qual número posso registrar?".freeze

    DEFAULT_EMAIL_PROMPT = "Se quiser, informe seu e-mail ou responda Pular.".freeze

    DEFAULT_THANK_YOU = "Obrigado, {primeiro_nome}! Já tenho seus dados. Você tem algum imóvel em mente ou quer ajuda para encontrar opções?"
    DEFAULT_AI_INSTRUCTIONS = "Atenda em português do Brasil, com cordialidade e mensagens curtas. Faça uma pergunta por vez. Considere o contexto da conversa e esclareça o que a pessoa procura, como cidade, bairro e faixa de preço."
    AI_INSTRUCTIONS_LIMIT = 3000

    def initialize(page, tenant:)
      @key = "instagram_capture_#{page.instagram_id}"
      @tenant = tenant
    end

    DATA_ACCESS = {
      "prices" => "Valores anunciados", "location" => "Localização pública", "details" => "Área, quartos, suítes e vagas",
      "features" => "Características e lazer", "financing" => "Financiamento e parcelamento cadastrados", "images" => "Fotos públicas"
    }.freeze
    MESSAGES = {
      "missing_both" => "Quero te ajudar! Para consultar o imóvel ou chamar um corretor, preciso do seu nome e telefone com DDD. Pode me enviar os dois?",
      "missing_name" => "Já registrei seu telefone. Falta só seu nome para continuar. Como posso te chamar?",
      "missing_phone" => "{primeiro_nome}, falta só seu telefone com DDD para consultar as informações ou encaminhar ao corretor. Qual número posso registrar?",
      "waiting_contact" => "Sua dúvida ficou registrada. Para continuar, aguardo {dados_faltantes}.",
      "identify_property" => "Para te passar a informação certa, pode me enviar o código ou o link do imóvel? Se precisar encontrar o anúncio, acesse {site_url}.",
      "handoff" => "Vou deixar sua mensagem com a equipe para continuar o atendimento."
    }.freeze
    ACTIONS = {"fixed" => "Resposta fixa", "ai" => "Resposta com IA", "handoff" => "Encaminhar ao corretor"}.freeze
    DEFAULT_CONDITIONS = [
      {"title" => "Pedido de atendimento humano", "match" => "handoff", "keywords" => "corretor;atendente;atendimento humano", "action" => "handoff", "enabled" => true, "ai_enabled" => true, "require_contact" => true},
      {"title" => "Dúvidas e busca de imóveis", "match" => "always", "keywords" => "", "action" => "ai", "enabled" => true, "ai_enabled" => true, "require_contact" => true}
    ].freeze

    def self.defaults
      {"enabled" => true, "sdr_enabled" => true, "typing_enabled" => true, "typing_seconds" => 2,
       "data_access" => DATA_ACCESS.keys, "conditions" => DEFAULT_CONDITIONS.map(&:dup)}.merge(MESSAGES)
    end

    def rules
      stored = JSON.parse(Setting.tenant_get(@key, "{}", tenant: @tenant))
      base = self.class.defaults.merge(stored.fetch("default", {}))
      stored.transform_values { |rule| base.merge(rule) }.merge("default" => base)
    end

    def self.interaction_options(settings)
      valid = true
      rule = {}
      if settings.key?(:typing_enabled)
        seconds = settings[:typing_seconds].to_s
        valid &&= seconds.match?(/\A[0-5]\z/)
        rule.merge!("typing_enabled" => settings[:typing_enabled] == "1", "typing_seconds" => seconds.to_i)
      end
      if settings.key?(:data_access)
        access = Array(settings[:data_access]).reject(&:blank?)
        valid &&= (access - DATA_ACCESS.keys).empty?
        rule["data_access"] = access
      end
      MESSAGES.each_key do |key|
        next unless settings.key?(key)
        text = settings[key].to_s.strip
        valid &&= text.present? && text.length <= Reply::MAX_CHARS
        rule[key] = text
      end
      if settings[:conditions_present] == "1"
        conditions = settings.fetch(:conditions, {}).to_h.values.reject { |condition| condition["_destroy"] == "1" }
        valid &&= conditions.size <= 20
        rule["conditions"] = conditions.sort_by { |condition| condition["position"].to_i }.map do |condition|
          valid &&= condition["title"].to_s.strip.present? && condition["title"].to_s.length <= 300 &&
            condition["keywords"].to_s.length <= 500 && condition["response"].to_s.length <= Reply::MAX_CHARS &&
            ACTIONS.key?(condition["action"]) && %w[context keywords handoff always].include?(condition["match"])
          valid &&= condition["response"].present? if condition["action"] == "fixed"
          condition.slice("title", "match", "keywords", "action", "response").merge(
            %w[enabled ai_enabled require_contact].index_with { |key| condition[key] == "1" })
        end
      end
      [rule, valid]
    end

    def self.allowed?(rule, key)
      Array(rule.fetch("data_access", DATA_ACCESS.keys)).include?(key)
    end

    def self.message(rule, key, lead)
      text = rule[key].presence || MESSAGES.fetch(key)
      site_url = "#{lead.tenant.public_base_url}/imoveis"
      if text.include?("{site_url}") && (token = PropertyJourney.reference(lead))
        site_url += "?#{ {ig_ref: token}.to_query }"
      end
      text.gsub("{primeiro_nome}", lead.client_name.to_s.split.first.presence || "Olá")
        .gsub("{site_url}", site_url)
        .gsub("{dados_faltantes}", [CaptureAnswer.new(lead.client_name).name.blank? ? "seu nome" : nil,
          CaptureAnswer.new(lead.display_phone.to_s).phone.blank? ? "seu telefone com DDD" : nil].compact.join(" e "))
        .first(Reply::MAX_CHARS)
    end

    def save(campaign_id:, enabled:, name_prompt:, phone_prompt:, ask_email: false, email_prompt: "", create_only: false)
      save_many(campaign_ids: [campaign_id], create_only: create_only, rule: {
          "enabled" => enabled, "sdr_enabled" => false, "name_prompt" => name_prompt, "phone_prompt" => phone_prompt,
          "ask_email" => ask_email, "email_prompt" => email_prompt
      })
    end

    def save_many(campaign_ids:, create_only:, rule:)
      @tenant.with_lock do
        existing = JSON.parse(Setting.tenant_get(@key, "{}", tenant: @tenant))
        next false if create_only && campaign_ids.any? { |id| existing.key?(id) }

        Setting.set(@key, existing.merge(campaign_ids.index_with { rule }).to_json, tenant: @tenant)
      end
    end

    def self.prompts(rule)
      name = rule["name_prompt"].presence
      phone = rule["phone_prompt"].presence
      # Atualiza apenas os antigos padrões; textos personalizados da conta são preservados.
      name = nil if name == "Olá! Como posso chamar você?"
      phone = nil if ["Qual é o seu telefone com DDD para nossa equipe continuar o atendimento?", "Qual é o seu WhatsApp com DDD? Se preferir, podemos continuar por aqui."].include?(phone)
      {
        "name_prompt" => name || DEFAULT_NAME_PROMPT,
        "phone_prompt" => phone || DEFAULT_PHONE_PROMPT,
        "email_prompt" => rule["email_prompt"].presence || DEFAULT_EMAIL_PROMPT,
        "thank_you_prompt" => rule["thank_you_prompt"].presence || DEFAULT_THANK_YOU
      }
    end
  end
end
