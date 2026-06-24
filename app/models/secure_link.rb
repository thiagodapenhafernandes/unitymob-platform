class SecureLink < ApplicationRecord
  belongs_to :lead
  belongs_to :issued_to_admin_user, class_name: "AdminUser", optional: true

  # Ações ao abrir o link: telefone (WhatsApp), email (mailto), ver o lead ou
  # aceitar (push — o clique vale como atendimento, dentro do prazo).
  enum action_type: { phone: 0, email: 1, view: 2, attend: 3 }

  scope :active_links, -> { where(active: true) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  before_validation :ensure_token, on: :create
  validates :token, presence: true, uniqueness: true

  # Pega um link reutilizável (mesmo lead/ação/corretor, ativo e não expirado) ou
  # cria um novo. expiry_days <= 0 => sem expiração.
  def self.link_for(lead, action_type, expiry_days:, issued_to: nil)
    existing = active_links.not_expired
                           .where(lead_id: lead.id, action_type: action_types[action_type.to_s], issued_to_admin_user_id: issued_to&.id)
                           .order(created_at: :desc).first
    return existing if existing

    create!(
      lead: lead,
      action_type: action_type,
      issued_to_admin_user: issued_to,
      expires_at: (expiry_days.to_i.positive? ? expiry_days.to_i.days.from_now : nil)
    )
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def valid_for_access?
    active? && !expired?
  end

  def record_access!
    now = Time.current
    update_columns(
      access_count: access_count + 1,
      first_accessed_at: first_accessed_at || now,
      last_accessed_at: now,
      updated_at: now
    )
  end

  def full_url
    "#{ENV['APP_HOST']}/s/#{token}"
  end

  private

  def ensure_token
    return if token.present?

    loop do
      candidate = SecureRandom.urlsafe_base64(32)
      unless SecureLink.exists?(token: candidate)
        self.token = candidate
        break
      end
    end
  end
end
