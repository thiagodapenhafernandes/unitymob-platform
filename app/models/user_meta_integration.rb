class UserMetaIntegration < ApplicationRecord
  belongs_to :admin_user
  belongs_to :tenant, optional: true
  has_many :meta_facebook_pages, dependent: :destroy
  has_many :meta_lead_forms, through: :meta_facebook_pages

  # Modelo agência: uma integração por usuário POR CONTA. Guards has_attribute?
  # mantêm o código funcional antes da migration 20260705000001.
  before_validation { self.tenant_id ||= admin_user&.tenant_id if has_attribute?(:tenant_id) }
  validates :tenant_id, presence: true, if: -> { has_attribute?(:tenant_id) }

  validates :access_token, presence: true
  validates :facebook_user_id, presence: true

  # Tenant efetivo mesmo pré-migration.
  def owner_tenant_id
    (tenant_id if has_attribute?(:tenant_id)) || admin_user&.tenant_id
  end

  def selected_ad_accounts
    ad_accounts.presence || (ad_account_id.present? ? {ad_account_id => ad_account_name} : {})
  end

  def ad_account_ids
    selected_ad_accounts.keys
  end

  def expired?
    token_expires_at.present? && token_expires_at < Time.current
  end

  # Do not expose provider messages: they can contain tokens or request URLs.
  def self.sync_failure_reason(error)
    return sync_failure_reason(error.cause) if error.is_a?(Facebook::MetaService::MetaAPIError) && error.cause
    return error.message if error.is_a?(Facebook::MetaService::MetaAPIError)

    case error
    when Koala::Facebook::APIError
      case error.fb_error_code.to_i
      when 190 then "A Meta recusou a autorização. Reconecte sua conta."
      when 10, 200 then "A Meta recusou o acesso. Confira as permissões e o acesso à página no negócio."
      else "A Meta não concluiu a consulta (código #{error.fb_error_code.to_i}). Tente novamente; se persistir, contate o suporte."
      end
    when Faraday::Error, Timeout::Error, SocketError
      "Falha de comunicação com a Meta. Tente novamente em instantes."
    else
      "Falha interna ao executar esta etapa. Tente novamente; se persistir, contate o suporte."
    end
  end
end
