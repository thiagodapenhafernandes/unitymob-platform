module Admin::PortalIntegrationsHelper
  DIRECT_LEAD_PORTALS = %w[casamineira chavesnamao].freeze

  def imovelweb_direct_leads?(integration)
    integration.portal.in?(%w[imovelweb imovelweb_2])
  end

  def portal_direct_lead_setup(integration)
    return unless DIRECT_LEAD_PORTALS.include?(integration.portal)

    if integration.portal == "chavesnamao"
      return {
        contact: "atendimento@chavesnamao.com.br",
        introduction: "Após configurar esta conta, encaminhe a URL ao portal e combine o envio de um lead de teste antes da ativação definitiva.",
        next_steps: "Confira o lead recebido, o imóvel, a fila e o destino configurado nesta conta. Combine a virada do fluxo atual para evitar a mesma consulta recebida por dois canais.",
        request: <<~TEXT.strip
          Assunto: Homologação de leads — #{current_tenant.name} / Unitymob / Chaves na Mão

          Solicitamos homologar o webhook imobiliário conforme https://chavesnamao.github.io/lead-documentation/.
          Conta anunciante: #{integration.account_id.presence || "informar o código da conta no portal"}.
          Encaminharemos a URL de recebimento desta conta, disponível acima, e o XML de imóveis disponível nesta tela.
          As credenciais são o e-mail de acesso e o Token Integração de leads da própria imobiliária, disponíveis em Meus Dados no portal.
          Por favor, combinem conosco um teste e a virada do destino atual. Não alterar a integração de anúncios.
          Também encaminharemos nome, site, logotipo e contatos técnicos da Unitymob, horários de atualização do XML e orientações de acesso às URLs.
        TEXT
      }
    end
    {
      contact: "atendimento@imovelweb.com.br",
      request: <<~TEXT.strip
        Assunto: Integração direta de leads — #{current_tenant.name} / Unitymob / #{integration.title}

        Solicitamos habilitar o recebimento dos leads de #{integration.title} diretamente no CRM Unitymob, sem passar pelo Gestor de Leads da OLX, preservando a integração atual de anúncios.
        Conta anunciante: #{integration.account_id.presence || "informar o código da conta no portal"}.

        Por favor, confirmem se aceitam um CRM próprio e se é necessária homologação. Precisamos da documentação de webhook ou API, exemplo de payload anonimizado, autenticação, identificação da conta e do imóvel, ID único do lead, política de reenvio e procedimento de teste.
        Informem se incluem contatos de formulários, WhatsApp e telefone, se há custo adicional e se é possível recuperar leads anteriores.
        A URL definitiva e as credenciais serão fornecidas após validarmos o contrato técnico. Não utilizem a URL do feed de imóveis ou o webhook de status de anúncios para enviar leads.
      TEXT
    }
  end

  def chaves_na_mao_connection_badge(connection)
    label, tone = if !connection.receiving?
      ["Desativado", :gray]
    elsif connection.operational?
      ["Ativado", :green]
    else
      ["Em validação", :amber]
    end
    ax_badge(label, tone: tone)
  end

  def portal_lead_connection_badge(integration)
    label, tone = if !Portal::LeadGatewayClient.configured?
      ["Suporte necessário", :amber]
    elsif integration.lead_gateway_error.present?
      ["Atualização pendente", :amber]
    elsif !integration.leads_receiving?
      ["Recebimento pausado", :amber]
    elsif integration.lead_gateway_synced_at.blank?
      ["Preparando conexão", :amber]
    elsif integration.last_lead_at.present?
      ["Lead recebido", :green]
    else
      ["Sem recebimento confirmado", :gray]
    end
    ax_badge(label, tone: tone)
  end
end
