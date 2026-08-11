class CommercialContractTermsVersion < ApplicationRecord
  DEFAULT_VERSION = "2026.08".freeze
  DEFAULT_TITLE = "Termos Gerais de Contratação Unitymob".freeze
  DEFAULT_BODY = <<~TEXT.squish.freeze
    A contratação da Unitymob é realizada em ambiente eletrônico, mediante aceite do representante da contratante, confirmação por código enviado ao e-mail informado e registro técnico das evidências de autoria e integridade. O plano Unitymob completo contempla o uso da plataforma para gestão imobiliária sem limitação contratual de quantidade de corretores, imóveis, leads ou funcionalidades padrão disponíveis na conta. Implantação assistida, migrações extraordinárias, customizações específicas, integrações sob demanda, consultorias ou serviços fora do escopo padrão poderão ser orçados separadamente. Custos de terceiros poderão ser repassados quando aplicáveis, incluindo infraestrutura de servidor, storage/armazenamento, tarifas da Meta/WhatsApp, consumo de OpenAI/IA e outros fornecedores externos necessários para funcionalidades ativadas pela contratante. A contratante declara que os dados informados são verdadeiros e que o representante possui poderes para contratar em seu nome. As partes reconhecem a validade da contratação e assinatura por meios eletrônicos disponibilizados pela Unitymob, inclusive autenticação, confirmação por e-mail, registros eletrônicos, IP, user-agent, data/hora, hash do documento apresentado e demais evidências técnicas, nos termos da legislação aplicável.
  TEXT

  belongs_to :tenant
  has_many :commercial_contract_proposals, foreign_key: :terms_version_id, dependent: :restrict_with_error

  validates :version, :title, :body, presence: true
  validates :version, uniqueness: { scope: :tenant_id }

  before_validation :ensure_hash
  before_validation :ensure_published_at, if: :active?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(published_at: :desc, created_at: :desc) }

  def self.current_for(tenant)
    active.where(tenant: tenant).ordered.first || create_default_for!(tenant)
  end

  def self.create_default_for!(tenant)
    create!(
      tenant: tenant,
      version: DEFAULT_VERSION,
      title: DEFAULT_TITLE,
      body: DEFAULT_BODY,
      published_at: Time.current,
      active: true
    )
  end

  def ensure_hash
    self.document_hash = Digest::SHA256.hexdigest([version, title, body].join("\n")) if body.present?
  end

  def ensure_published_at
    self.published_at ||= Time.current
  end
end
