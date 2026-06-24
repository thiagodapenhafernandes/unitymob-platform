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
