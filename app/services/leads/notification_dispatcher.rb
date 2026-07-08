module Leads
  # Dispara notificações pro corretor recém-atribuído, obedecendo as flags
  # da DistributionRule (notify_whatsapp, notify_email, notify_push,
  # notify_webhook). Chamado após o Lead ser vinculado a um admin_user.
  #
  # Todas as entregas são best-effort (erro em uma não bloqueia as outras).
  class NotificationDispatcher
    def self.deliver(lead, sticky: false)
      new(lead, sticky: sticky).deliver
    end

    # Shark Tank: notifica TODOS os corretores da regra (o 1º que aceitar vira dono).
    def self.notify_shark_tank(lead, rule, candidates: nil)
      return unless LeadSetting.instance.notify_on_shark_tank?
      return unless rule

      dispatcher = new(lead)
      scope = candidates || rule.distribution_rule_agents
      scope.includes(:admin_user).each do |dra|
        agent = dra.admin_user
        dispatcher.deliver_to_agent(agent) if agent
      end
    end

    # ---- Eventos extras (push ao corretor), controlados em LeadSetting ----------

    # Lead que já chega com corretor (share link / atribuição manual na criação).
    def self.notify_direct_assignment(lead)
      return unless LeadSetting.instance.notify_on_direct_assignment?

      push_to(lead.admin_user,
              title: "Novo lead: #{lead.display_name}",
              body:  "#{lead.display_phone} · Origem: #{lead.origin}",
              url:   "/admin/leads/#{lead.id}/attend")
    end

    # Reatribuição manual do corretor pelo admin.
    def self.notify_reassignment(lead, new_corretor)
      return unless LeadSetting.instance.notify_on_reassignment?

      push_to(new_corretor,
              title: "Lead atribuído a você: #{lead.display_name}",
              body:  "#{lead.display_phone} · Origem: #{lead.origin}",
              url:   "/admin/leads/#{lead.id}/attend")
    end

    # Avisa o corretor que perdeu o lead por não atender no prazo (pocket).
    def self.notify_lost_turn(lead, previous_corretor)
      return unless LeadSetting.instance.notify_on_lost_turn?

      push_to(previous_corretor,
              title: "Você perdeu o lead #{lead.display_name}",
              body:  "Não atendido no prazo — foi redistribuído para outro corretor.",
              url:   "/admin/leads")
    end

    def self.push_to(corretor, title:, body:, url:)
      return unless corretor

      # high: com urgency normal o Android em Doze (aparelho parado) segura a
      # entrega — exatamente o "push parou de chegar" com o celular na mesa.
      Notifications::PushDispatcher.deliver(admin_user_id: corretor.id, title: title, body: body, url: url, urgency: "high", ttl: 3600)
    rescue => e
      Rails.logger.warn("[LeadNotify] push de evento falhou pro corretor #{corretor&.id}: #{e.message}")
    end

    def initialize(lead, sticky: false)
      @lead = lead
      @rule = lead.distribution_rule
      @corretor = lead.admin_user
      @sticky = sticky
    end

    def deliver
      return unless @rule && @corretor
      return unless distribution_event_enabled?

      deliver_channels
    end

    # Envia a notificação da regra para um corretor específico (usado no Shark Tank,
    # que notifica todos os corretores elegíveis da regra).
    def deliver_to_agent(agent)
      return unless @rule && agent

      @corretor = agent
      deliver_channels
    end

    private

    # Gating por tipo de evento de distribuição (toggles em LeadSetting).
    def distribution_event_enabled?
      setting = LeadSetting.instance
      if @sticky
        setting.notify_on_sticky?
      elsif redistribution?
        setting.notify_on_redistribution?
      else
        setting.notify_on_distribution?
      end
    end

    # É uma redistribuição (lead já passou por pocket expirado antes)?
    def redistribution?
      @lead.activities.where(kind: "pocket_expired").exists?
    end

    def deliver_channels
      begin
        deliver_push if @rule.notify_push
      rescue => e
        log_notification(:push, :failed, error: e.message)
        Rails.logger.warn("[LeadNotify] push falhou: #{e.message}")
      end

      begin
        deliver_whatsapp if @rule.notify_whatsapp
      rescue => e
        log_notification(:whatsapp, :failed, error: e.message)
        Rails.logger.warn("[LeadNotify] whatsapp falhou: #{e.message}")
      end

      begin
        deliver_email if @rule.notify_email
      rescue => e
        log_notification(:email, :failed, error: e.message)
        Rails.logger.warn("[LeadNotify] email falhou: #{e.message}")
      end

      begin
        deliver_webhook if @rule.notify_webhook
      rescue => e
        log_notification(:webhook, :failed, error: e.message)
        Rails.logger.warn("[LeadNotify] webhook falhou: #{e.message}")
      end
    end

    private

    def deliver_push
      links = Leads::ContactLinks.new(@lead, @corretor)
      secure = links.secure?(:push)
      click_action = PushSetting.instance.lead_click_action_value

      # Endpoint que marca o lead como atendido no prazo (mesmo motor do link seguro).
      attend_url = secure ? links.url(:attend) : admin_attend_url

      # Padrão "WhatsApp": o clique abre a conversa do lead direto e o service worker
      # avisa o sistema do aceite em background (beacon) — sem tela intermediária.
      whatsapp = @lead.direct_whatsapp_url if click_action == "whatsapp"

      if whatsapp.present?
        url = whatsapp
        accept_url = secure ? "#{attend_url}?ack=1" : attend_url
      else
        # Detalhes primeiro: usa o card seguro do lead e marca o aceite ao abrir.
        # Mesmo com mascaramento desativado, o push precisa de uma URL segura fora
        # do admin para funcionar bem no PWA/aparelho do corretor.
        url = "#{links.url(:attend)}?details=1"
        accept_url = nil
      end

      body = secure ? "Toque para atender · Origem: #{@lead.origin}" : "#{@lead.display_phone} · Origem: #{@lead.origin}"

      sent = Notifications::PushDispatcher.deliver(
        admin_user_id: @corretor.id,
        title: "Novo lead: #{@lead.display_name}",
        body:  body,
        url:   url,
        accept_url: accept_url,
        tag: "lead-#{@lead.id}-#{@corretor.id}",
        urgency: "high",
        ttl: 900,
        require_interaction: true
      )
      if sent.to_i.zero?
        log_notification(:push, :skipped, reason: "no_active_subscription")
        Rails.logger.warn("[LeadNotify] push nao enviado lead=#{@lead.id} corretor=#{@corretor.id}")
      else
        log_notification(:push, :sent, target: @corretor.id, count: sent.to_i)
      end
    end

    def admin_attend_url
      host = ENV["APP_HOST"].presence
      path = "/admin/leads/#{@lead.id}/attend"
      host ? "#{host}#{path}" : path
    end

    # Template aprovado para notificar o corretor de um novo lead (pt_BR).
    WHATSAPP_LEAD_TEMPLATE = "lead_agent_v4".freeze

    # Notifica o corretor recém-atribuído via WhatsApp Business (Cloud API) usando
    # o template aprovado — funciona dentro e fora da janela de 24h. O TRANSPORTE
    # (integração do tenant OU sender global opt-in) vem do TransportResolver; o
    # ALVO continua sendo o corretor do tenant.
    def deliver_whatsapp
      transport = Notifications::TransportResolver.whatsapp(@lead.tenant)
      return log_notification(:whatsapp, :skipped, reason: "transport_unavailable") unless transport

      sender = transport.sender

      phone = @corretor.phone.presence
      return log_notification(:whatsapp, :skipped, reason: "broker_phone_blank") if phone.blank?

      template_setting = whatsapp_template_setting
      template_params = whatsapp_template_params(template_setting)
      components = template_params.present? ? [{ type: "body", parameters: template_params }] : []

      result = Whatsapp::CloudClient.new(sender).send_template(
        to: phone,
        name: whatsapp_template_name(sender, template_setting),
        language: "pt_BR",
        components: components
      )

      if result[:ok]
        log_notification(:whatsapp, :sent, transport: transport.source, target: normalized_target(phone), message_id: result[:message_id])
      else
        log_notification(:whatsapp, :failed, transport: transport.source, target: normalized_target(phone), error: result[:error], status: result[:status], meta_error: result[:meta_error])
        Rails.logger.warn("[LeadNotify] whatsapp template falhou pro corretor #{@corretor.id}: #{result[:error]}")
      end
    end

    # Template do aviso de lead: usa a configuração por finalidade da conta.
    # O sender global ainda pode trazer template_name próprio; o fallback evita
    # quebrar instalações antigas até configurarem a tela de integrações.
    def whatsapp_template_setting
      NotificationTemplateSetting.setting_for(
        tenant: @lead.tenant,
        purpose: "lead_distribution_broker"
      )
    end

    def whatsapp_template_name(sender, setting = nil)
      setting&.whatsapp_template&.name.presence ||
        (sender.respond_to?(:template_name) && sender.template_name.presence) ||
        WHATSAPP_LEAD_TEMPLATE
    end

    # Parâmetros do corpo do template configurado para a finalidade.
    # Sem configuração, mantém a ordem histórica do lead_agent_v4:
    # {{1}} cliente · {{2}} origem · {{3}} nome · {{4}} telefone · {{5}} email · {{6}} outros dados.
    # Com "link seguro" ligado, telefone/email/dados viram links /s/token (só o nome
    # fica visível) e o clique vira o evento de atendimento (sistema intermediário).
    def whatsapp_template_params(setting = nil)
      return default_whatsapp_template_params unless setting&.whatsapp_template

      count = setting.whatsapp_template.variable_count
      return [] if count.zero?

      mapping = setting.variable_mapping
      (1..count).map do |index|
        whatsapp_text_param(whatsapp_variable_value(mapping[index.to_s]))
      end
    end

    def default_whatsapp_template_params
      %w[
        lead_name
        lead_origin
        lead_name
        lead_phone_or_link
        lead_email_or_link
        lead_other_or_link
      ].map { |source| whatsapp_text_param(whatsapp_variable_value(source)) }
    end

    def whatsapp_variable_value(source)
      links = Leads::ContactLinks.new(@lead, @corretor)

      case source.to_s
      when "lead_name"
        @lead.display_name
      when "lead_origin"
        @lead.origin
      when "lead_phone_or_link"
        links.secure?(:whatsapp) ? links.url(:phone) : @lead.display_phone
      when "lead_email_or_link"
        links.secure?(:whatsapp) ? links.url(:email) : @lead.display_email
      when "lead_other_or_link"
        links.secure?(:whatsapp) ? links.url(:view) : (@lead.product.presence || @lead.origin)
      when "broker_name"
        @corretor.name
      when "broker_phone"
        @corretor.phone
      when "broker_email"
        @corretor.notification_email
      else
        nil
      end
    end

    # A Cloud API rejeita parâmetros vazios ou com quebra de linha / espaços longos.
    def whatsapp_text_param(value)
      text = value.to_s.gsub(/\s+/, " ").strip
      text = "—" if text.blank?
      { type: "text", text: text }
    end

    # TRANSPORTE de e-mail resolvido por conta (SMTP próprio ou global opt-in);
    # o ALVO continua sendo o corretor do tenant. Sem SMTP disponível, não envia.
    def deliver_email
      transport = Notifications::TransportResolver.email(@lead.tenant)
      return log_notification(:email, :skipped, reason: "transport_unavailable") unless transport
      return log_notification(:email, :skipped, reason: "broker_email_blank") if @corretor.notification_email.blank?

      job = LeadMailer.with(lead: @lead, corretor: @corretor).lead_assigned.deliver_later
      log_notification(:email, :sent, transport: transport.source, target: @corretor.notification_email, job_id: job&.job_id)
    end

    # Dispara o lead COMPLETO (dados + histórico + corretor + gestor) para todas as
    # URLs configuradas na regra (multi-valor). Cada URL vira um job assíncrono pra
    # não travar a distribuição em múltiplos POSTs externos (com retry/backoff).
    # Sem URLs na regra, faz fallback pro webhook global legado (WebhookSetting).
    def deliver_webhook
      urls = @rule.notify_webhook_url_list
      if urls.blank?
        setting = WebhookSetting.first
        urls = [setting.webhook_url] if setting&.webhook_url.present?
      end
      return if urls.blank?

      payload = event_payload("webhook").as_json
      urls.each { |url| Leads::WebhookDeliveryJob.perform_later(url, payload) }
      log_notification(:webhook, :sent, count: urls.size)
    end

    def log_notification(channel, status, metadata = {})
      LeadActivity.log!(
        lead: @lead,
        kind: "notification_#{status}",
        metadata: {
          channel: channel.to_s,
          rule_id: @rule&.id,
          rule_name: @rule&.name,
          admin_user_id: @corretor&.id,
          admin_user_name: @corretor&.name
        }.merge(metadata.compact)
      )
    end

    def normalized_target(value)
      value.to_s.gsub(/\D/, "")
    end

    def event_payload(channel)
      {
        event: "lead.distributed",
        channel: channel,
        lead: lead_payload,
        history: history_payload,
        corretor: corretor_payload,
        gestor: gestor_payload,
        rule: rule_payload
      }
    end

    # Lead completo: todos os atributos persistidos + campos derivados de exibição.
    def lead_payload
      @lead.attributes.merge(
        "display_name" => @lead.display_name,
        "display_phone" => @lead.display_phone,
        "display_email" => @lead.display_email,
        "created_at" => @lead.created_at&.iso8601,
        "updated_at" => @lead.updated_at&.iso8601
      )
    end

    # Histórico completo do lead (timeline cronológica).
    def history_payload
      @lead.activities.chronological.map do |activity|
        {
          kind: activity.kind,
          metadata: activity.metadata,
          created_at: activity.created_at&.iso8601
        }
      end
    end

    def corretor_payload
      {
        id: @corretor.id,
        name: @corretor.name,
        phone: @corretor.phone,
        email: @corretor.notification_email,
        role: @corretor.role,
        manager_id: @corretor.manager_id
      }
    end

    # Gestor (manager) do corretor que recebeu o lead — nil se não houver.
    def gestor_payload
      manager = @corretor.manager
      return nil unless manager

      {
        id: manager.id,
        name: manager.name,
        phone: manager.phone,
        email: manager.notification_email
      }
    end

    def rule_payload
      {
        id: @rule.id,
        name: @rule.name
      }
    end
  end
end
