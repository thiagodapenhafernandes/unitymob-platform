module Automation
  module EventCatalog
    EVENTS = {
      "lead_created" => {
        label: "Lead criado",
        description: "Observa quando um novo lead passa a existir na plataforma."
      },
      "lead_stage_changed" => {
        label: "Lead mudou de etapa",
        description: "Observa mudanças de etapa/status depois que o lead já existe."
      },
      "lead_assigned" => {
        label: "Lead atribuído",
        description: "Observa quando a distribuição entrega um lead para um corretor."
      },
      "lead_idle" => {
        label: "Lead parado",
        description: "Observa leads sem andamento pelo tempo configurado."
      },
      "proposal_viewed" => {
        label: "Proposta visualizada",
        description: "Observa quando o cliente abre uma proposta pública."
      },
      "proposal_accepted" => {
        label: "Proposta aceita",
        description: "Observa quando o cliente aceita uma proposta."
      },
      "proposal_rejected" => {
        label: "Proposta recusada",
        description: "Observa quando o cliente recusa uma proposta."
      },
      "whatsapp_received" => {
        label: "WhatsApp recebido",
        description: "Observa quando o lead envia uma mensagem para a plataforma."
      },
      "whatsapp_campaign_started" => {
        label: "Disparo WhatsApp iniciado",
        description: "Observa quando uma campanha de WhatsApp começa a processar sua audiência."
      },
      "whatsapp_campaign_completed" => {
        label: "Disparo WhatsApp concluído",
        description: "Observa quando uma campanha de WhatsApp termina seus envios."
      },
      "whatsapp_campaign_failed" => {
        label: "Disparo WhatsApp com erro",
        description: "Observa falhas críticas no processamento de uma campanha WhatsApp."
      },
      "whatsapp_campaign_message_sent" => {
        label: "Mensagem de disparo enviada",
        description: "Observa quando uma mensagem de campanha é aceita pela Cloud API."
      },
      "whatsapp_campaign_message_delivered" => {
        label: "Mensagem de disparo entregue",
        description: "Observa quando a Meta confirma entrega de uma mensagem de campanha."
      },
      "whatsapp_campaign_message_read" => {
        label: "Mensagem de disparo lida",
        description: "Observa quando a Meta confirma leitura de uma mensagem de campanha."
      },
      "whatsapp_campaign_message_failed" => {
        label: "Mensagem de disparo falhou",
        description: "Observa quando uma mensagem de campanha falha."
      },
      "whatsapp_campaign_message_replied" => {
        label: "Destinatário respondeu disparo",
        description: "Observa quando uma resposta ou clique do destinatário é associado a uma campanha WhatsApp."
      },
      "scheduled_routine" => {
        label: "Rotina agendada",
        description: "Executa uma intervenção recorrente sobre leads que atendem aos filtros configurados."
      },
      "interest_profile_detected" => {
        label: "Interesse em imóveis detectado",
        description: "Observa quando a navegação e os dados do lead formam um perfil de interesse."
      },
      "matching_property_found" => {
        label: "Imóvel compatível encontrado",
        description: "Observa quando a Inteligência de Interesse encontra imóveis aderentes ao perfil do lead."
      },
      "lead_without_matching_property" => {
        label: "Lead sem imóvel compatível",
        description: "Observa quando há perfil de interesse, mas nenhum imóvel atual atende bem aos critérios."
      },
      "interest_profile_incomplete" => {
        label: "Perfil de interesse incompleto",
        description: "Observa quando faltam sinais suficientes para recomendar imóveis com segurança."
      },
      "interested_property_price_dropped" => {
        label: "Imóvel de interesse baixou preço",
        description: "Observa queda de preço em imóvel já associado ao interesse do lead."
      },
      "lead_repeated_similar_property_views" => {
        label: "Lead visitou imóveis parecidos",
        description: "Observa repetição de navegação em imóveis com perfil semelhante."
      }
    }.freeze

    module_function

    def names
      EVENTS.keys
    end

    def include?(name)
      EVENTS.key?(name.to_s)
    end

    def label(name)
      EVENTS.dig(name.to_s, :label) || name.to_s.humanize
    end

    def description(name)
      EVENTS.dig(name.to_s, :description).to_s
    end
  end
end
