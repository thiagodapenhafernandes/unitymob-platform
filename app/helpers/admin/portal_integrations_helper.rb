module Admin::PortalIntegrationsHelper
  DIRECT_LEAD_PORTALS = %w[imovelweb imovelweb_2 casamineira chavesnamao].freeze

  def portal_direct_lead_setup(integration)
    return unless DIRECT_LEAD_PORTALS.include?(integration.portal)

    chaves = integration.portal == "chavesnamao"
    {
      contact: chaves ? "atendimento@chavesnamao.com.br" : "atendimento@imovelweb.com.br",
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
