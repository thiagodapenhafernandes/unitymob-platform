class PublicFormSubmission < ApplicationRecord
  include TenantScoped

  STATUSES = %w[received delivered failed].freeze

  belongs_to :public_form
  belongs_to :lead, optional: true
  has_many_attached :files

  validates :payload, :source, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :public_form_same_tenant

  before_validation :assign_tenant_from_public_form
  before_validation :extract_normalized_contact

  scope :recent, -> { order(created_at: :desc) }
  scope :searching, ->(term) {
    sanitized = ActiveRecord::Base.sanitize_sql_like(term.to_s.strip)
    where("normalized_name ILIKE :q OR normalized_email ILIKE :q OR normalized_phone ILIKE :q", q: "%#{sanitized}%")
  }
  scope :within_period, ->(days) {
    where(created_at: days.to_i.days.ago..) if days.to_s.in?(%w[7 30])
  }

  private

  def assign_tenant_from_public_form
    self.tenant ||= public_form&.tenant
  end

  def extract_normalized_contact
    self.normalized_name = payload["name"].to_s.strip.presence || payload["nome"].to_s.strip.presence
    self.normalized_email = payload["email"].to_s.strip.downcase.presence

    phone_value = payload["phone"].presence || payload["telefone"].presence || payload["whatsapp"].presence
    self.normalized_phone = Phones::Normalizer.call(phone_value).to_s.presence if phone_value.present?
  end

  def public_form_same_tenant
    return if public_form.blank? || tenant.blank? || public_form.tenant_id == tenant_id

    errors.add(:public_form, "deve pertencer à mesma conta")
  end
end
