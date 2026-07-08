class PortalIntegration < ApplicationRecord
  include TenantScoped

  PORTAL_DEFINITIONS = {
    "zapimoveis" => { title: "ZapImóveis", feed_strategy: "vrsync_xml" },
    "vivareal_vrsync" => { title: "Viva Real VRSync", feed_strategy: "vrsync_xml" },
    "imovelweb" => { title: "Imovelweb", feed_strategy: "olx_xml" },
    "imovelweb_2" => { title: "Imovelweb 2", feed_strategy: "olx_xml" },
    "chavesnamao" => { title: "Chaves na Mão", feed_strategy: "chaves_xml" },
    "casamineira" => { title: "Casa Mineira", feed_strategy: "vrsync_xml" },
    "lais_ai" => { title: "Lais Ai", feed_strategy: "vrsync_xml" },
    "netimoveis2" => { title: "Netimoveis 2", feed_strategy: "vrsync_xml" }
  }.freeze

  PORTALS = PORTAL_DEFINITIONS.keys.freeze
  BUSINESS_TYPES = %w[venda aluguel].freeze

  # Documentação e instruções para cada portal — exibidas na UI para ajudar o usuário
  PORTAL_HELP = {
    "zapimoveis" => {
      docs_url: "https://ajuda.gruporbi.com.br/hc/pt-br/articles/360045195371",
      summary: "Feed XML no padrão VRSync. O ZapImóveis lê automaticamente em intervalos definidos pela conta.",
      setup_steps: [
        "Acesse seu painel do ZapImóveis e copie o ID da conta (Account ID).",
        "Cole o Account ID no campo abaixo e ative a integração.",
        "Marque os imóveis que devem ir para o ZapImóveis na ficha do imóvel (campo \"Publicar Imovelweb 2/ZapImóveis\").",
        "Copie a URL do Feed e informe ao gerente de conta do ZapImóveis."
      ]
    },
    "vivareal_vrsync" => {
      docs_url: "https://ajuda.gruporbi.com.br/hc/pt-br/articles/360045195371",
      summary: "Feed XML no padrão VRSync. O Viva Real consome o feed periodicamente (geralmente a cada 4-6h).",
      setup_steps: [
        "Acesse o painel Viva Real e localize o ID da conta.",
        "Configure Account ID, ative a integração e defina os tipos de negócio (venda/aluguel).",
        "Na ficha de cada imóvel, marque \"Publicar Viva Real\" e configure o tipo de publicação (padrão, destaque, super destaque, etc.).",
        "Envie a URL do Feed para o suporte do Viva Real."
      ]
    },
    "imovelweb" => {
      docs_url: "https://developers.olx.com.br/anuncio/xml/real_estate/home.html",
      summary: "Feed XML no padrão OLX (Imovelweb integra via OLX Brasil). Tags em PT-BR. Processado a cada 12h.",
      setup_steps: [
        "Solicite Account ID e Publisher ID ao gerente comercial do Imovelweb/OLX.",
        "Configure os IDs no formulário e ative a integração.",
        "Marque os imóveis com \"Publicar Imovelweb\" na ficha. Configure tipo de publicação e visibilidade do mapa.",
        "Envie a URL do Feed para a equipe técnica do Imovelweb (suporteintegrador@olxbr.com)."
      ]
    },
    "imovelweb_2" => {
      docs_url: "https://developers.olx.com.br/anuncio/xml/real_estate/home.html",
      summary: "Segunda conta Imovelweb (mesmo XML OLX). Útil quando a empresa tem 2 contratos no portal.",
      setup_steps: [
        "Solicite Account ID e Publisher ID da SEGUNDA conta Imovelweb.",
        "Configure os IDs e ative a integração.",
        "Marque os imóveis específicos para esta conta com \"Publicar Imovelweb 2\" e ajuste tipo de publicação.",
        "Envie a URL do Feed para a equipe técnica desta conta."
      ]
    },
    "chavesnamao" => {
      docs_url: "https://www.chavesnamao.com.br/integracoes-imobiliarias",
      summary: "Feed XML proprietário do Chaves na Mão. O portal lê o feed automaticamente.",
      setup_steps: [
        "Cadastre o token combinado com o suporte do Chaves na Mão.",
        "Configure o Account ID se aplicável e ative a integração.",
        "Para cada imóvel: marque \"Publicar Chaves na Mão\", defina destaque (sim/não) e período de locação.",
        "Envie a URL do Feed ao suporte do portal."
      ]
    },
    "casamineira" => {
      docs_url: "https://www.casamineira.com.br/parcerias",
      summary: "Feed XML no padrão VRSync (compatível com vários portais regionais).",
      setup_steps: [
        "Solicite acesso ao programa de parceiros Casa Mineira.",
        "Ative a integração e marque os imóveis com \"Publicar Casa Mineira\".",
        "Para destaques na home da Casa Mineira, configure o modelo (simples, destaque, home_destaque).",
        "Compartilhe a URL do Feed com o portal."
      ]
    },
    "lais_ai" => {
      docs_url: "https://lais.ai",
      summary: "Lais Ai — assistente de IA para imobiliárias. Consome feed XML VRSync.",
      setup_steps: [
        "Configure conta Lais Ai e ative a integração.",
        "Marque os imóveis que devem alimentar a IA com \"Publicar Lais Ai\".",
        "Compartilhe a URL do Feed com a equipe Lais."
      ]
    },
    "netimoveis2" => {
      docs_url: "https://www.netimoveis.com",
      summary: "Rede Netimoveis — feed XML VRSync.",
      setup_steps: [
        "Solicite acesso de integração à equipe Netimoveis.",
        "Ative a integração e marque os imóveis com \"Publicar Netimoveis 2\".",
        "Envie a URL do Feed ao suporte."
      ]
    }
  }.freeze

  validates :portal, presence: true, inclusion: { in: PORTALS }
  # Unicidade do portal é POR TENANT após a migration (tenant_id + portal).
  # Antes da migration (coluna ausente), mantém unicidade global — tolerante.
  if column_names.include?("tenant_id")
    validates :portal, uniqueness: { scope: :tenant_id }
  else
    validates :portal, uniqueness: true
  end
  validates :allowed_business_types, presence: true
  # feed_token permanece único GLOBALMENTE: é a chave pública do feed e
  # identifica sozinho a integração/tenant no lookup público.
  validates :feed_token, presence: true, uniqueness: true

  # Estados/eventos casam por portal string. Quando há tenant_id nas duas
  # pontas, escopamos a associação também por tenant para não cruzar registros
  # de outros tenants que compartilhem o mesmo nome de portal.
  if column_names.include?("tenant_id") &&
     (PortalIntegrationEvent.column_names.include?("tenant_id") rescue false)
    has_many :portal_integration_events,
             ->(integration) { where(tenant_id: integration.tenant_id) },
             primary_key: :portal, foreign_key: :portal,
             inverse_of: :portal_integration, dependent: :delete_all
  else
    has_many :portal_integration_events, primary_key: :portal, foreign_key: :portal, inverse_of: :portal_integration, dependent: :delete_all
  end

  if column_names.include?("tenant_id") &&
     (PortalListingState.column_names.include?("tenant_id") rescue false)
    has_many :portal_listing_states,
             ->(integration) { where(tenant_id: integration.tenant_id) },
             primary_key: :portal, foreign_key: :portal,
             inverse_of: :portal_integration, dependent: :delete_all
  else
    has_many :portal_listing_states, primary_key: :portal, foreign_key: :portal, inverse_of: :portal_integration, dependent: :delete_all
  end

  before_validation :normalize_values
  before_validation :ensure_feed_token

  scope :enabled, -> { where(enabled: true) }

  # Resolve (ou cria) a integração de um portal SEMPRE dentro de um tenant.
  # Uso escopado: current_tenant.portal_integrations.for_portal!(portal)
  #   — o tenant é inferido do current_scope da associação.
  # Uso explícito: PortalIntegration.for_portal!(portal, tenant: current_tenant)
  #   — tolerante enquanto Tenant não expõe a associação portal_integrations.
  # Exige um tenant: sem ele o método levanta erro (nunca cria registro global).
  def self.for_portal!(portal, tenant: nil)
    normalized = portal.to_s.downcase
    raise ActiveRecord::RecordNotFound, "Portal inválido" unless PORTALS.include?(normalized)

    tenant ||= scoped_tenant
    if column_names.include?("tenant_id")
      raise ActiveRecord::RecordNotFound, "Tenant não informado" if tenant.blank?

      relation = where(tenant_id: tenant.respond_to?(:id) ? tenant.id : tenant)
    else
      # Pré-migration: sem coluna tenant_id, opera global (comportamento antigo).
      relation = all
    end

    relation.find_or_initialize_by(portal: normalized).tap do |config|
      if config.new_record?
        # Quando escopado por where(tenant_id:), o novo registro já herda o
        # tenant_id do escopo. Só reforçamos com o objeto Tenant quando temos um.
        config.tenant = tenant if config.respond_to?(:tenant=) && tenant.is_a?(Tenant)
        config.allowed_statuses = Habitation::STATUS_OPTIONS
        config.allowed_business_types = BUSINESS_TYPES
        config.require_exibir_no_site = true
        config.operational_status = "idle"
        config.save!
      end
    end
  end

  # Tenant amarrado ao current_scope quando chamado a partir de uma associação
  # escopada (ex.: current_tenant.portal_integrations). Retorna o id/valor
  # presente no where do escopo corrente, ou nil.
  def self.scoped_tenant
    return nil unless column_names.include?("tenant_id")

    scope = current_scope
    return nil if scope.nil?

    scope.where_values_hash["tenant_id"]
  end
  private_class_method :scoped_tenant

  def masked_feed_token
    return nil if feed_token.blank?
    "********#{feed_token.to_s.last(4)}"
  end

  def masked_webhook_secret
    return nil if webhook_secret.blank?
    "********#{webhook_secret.to_s.last(4)}"
  end

  def title
    PORTAL_DEFINITIONS.dig(portal, :title) || portal.to_s.titleize
  end

  def feed_strategy
    PORTAL_DEFINITIONS.dig(portal, :feed_strategy) || "vrsync_xml"
  end

  def feed_format
    case feed_strategy
    when "olx_json" then :json
    else :xml
    end
  end

  def requires_account_id?
    %w[olx_xml olx_json].include?(feed_strategy)
  end

  def help
    PORTAL_HELP[portal] || {}
  end

  def docs_url
    help[:docs_url]
  end

  def summary
    help[:summary]
  end

  def setup_steps
    Array(help[:setup_steps])
  end

  # Lista de checagens de configuração. Cada item: { label:, ok:, hint: }.
  # Usado na UI para mostrar checklist visual ao usuário.
  def setup_checklist(eligible_count: nil)
    items = []

    items << {
      label: "Integração ativada",
      ok: enabled?,
      hint: enabled? ? nil : "Ative no toggle abaixo quando estiver tudo configurado."
    }

    items << {
      label: "Token do Feed gerado",
      ok: feed_token.present?,
      hint: feed_token.present? ? nil : "O token é gerado automaticamente ao salvar."
    }

    if requires_account_id?
      items << {
        label: "Account ID configurado",
        ok: account_id.present?,
        hint: account_id.present? ? nil : "Solicite ao portal e cole aqui."
      }
      items << {
        label: "Publisher ID configurado",
        ok: publisher_id.present?,
        hint: publisher_id.present? ? nil : "Solicite ao portal e cole aqui."
      }
    end

    items << {
      label: "Tipos de negócio definidos",
      ok: allowed_business_types.present?,
      hint: allowed_business_types.present? ? nil : "Selecione pelo menos um (venda/aluguel)."
    }

    items << {
      label: "Status permitidos definidos",
      ok: allowed_statuses.present?,
      hint: allowed_statuses.present? ? nil : "Defina quais status (Venda, Aluguel, etc.) entram no feed."
    }

    if eligible_count
      items << {
        label: "Imóveis elegíveis para envio",
        ok: eligible_count.to_i > 0,
        hint: eligible_count.to_i > 0 ? "#{eligible_count} imóveis prontos." : "Marque imóveis com a flag de publicação deste portal na ficha do imóvel."
      }
    end

    items
  end

  # Status agregado para a UI: :ready, :needs_config, :disabled, :no_eligible
  def readiness_status(eligible_count: nil)
    return :disabled unless enabled?

    checklist = setup_checklist(eligible_count: eligible_count)
    config_items = checklist.reject { |item| item[:label] == "Imóveis elegíveis para envio" }
    return :needs_config if config_items.any? { |item| !item[:ok] }
    return :no_eligible if eligible_count && eligible_count.to_i.zero?

    :ready
  end

  def readiness_label(status = nil)
    status ||= readiness_status
    {
      ready: "Pronto",
      needs_config: "Falta configurar",
      disabled: "Desativado",
      no_eligible: "Sem imóveis elegíveis"
    }[status]
  end

  def readiness_color(status = nil)
    status ||= readiness_status
    {
      ready: "success",
      needs_config: "warning",
      disabled: "secondary",
      no_eligible: "warning"
    }[status]
  end

  private

  def normalize_values
    self.portal = portal.to_s.downcase.strip
    self.allowed_statuses = Array(allowed_statuses).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    self.allowed_business_types = Array(allowed_business_types).map(&:to_s).map(&:strip).reject(&:blank?).uniq & BUSINESS_TYPES

    self.allowed_statuses = Habitation::STATUS_OPTIONS if allowed_statuses.blank?
    self.allowed_business_types = BUSINESS_TYPES if allowed_business_types.blank?
    self.operational_status = operational_status.to_s.presence || "idle"
  end

  def ensure_feed_token
    return if feed_token.present?

    self.feed_token = loop do
      candidate = SecureRandom.hex(24)
      break candidate unless self.class.where.not(id: id).exists?(feed_token: candidate)
    end
  end
end
