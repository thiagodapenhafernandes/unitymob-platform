class CommercialContractProposal < ApplicationRecord
  STATUSES = %w[draft sent viewed otp_pending accepted canceled expired].freeze
  STATUS_LABELS = {
    "draft" => "Rascunho",
    "sent" => "Enviada",
    "viewed" => "Visualizada",
    "otp_pending" => "Aguardando código",
    "accepted" => "Aceita",
    "canceled" => "Cancelada",
    "expired" => "Expirada"
  }.freeze

  DEFAULT_SCOPE = <<~TEXT.squish.freeze
    Plataforma Unitymob completa para operação imobiliária, com CRM de leads, cadastro e publicação de imóveis, corretores, funil, automações, site público, WhatsApp, BI operacional e recursos padrão disponíveis para a conta, sem limitação contratual de quantidade de imóveis, corretores, leads ou funcionalidades padrão.
  TEXT

  DEFAULT_EXTERNAL_COSTS = <<~TEXT.squish.freeze
    O valor mensal da Unitymob não inclui custos cobrados por terceiros. Quando aplicável, poderão ser repassados custos de servidor, storage/armazenamento, Meta/WhatsApp, OpenAI/IA e outros fornecedores externos necessários para recursos ativados pela contratante.
  TEXT

  belongs_to :tenant
  belongs_to :admin_user
  belongs_to :terms_version, class_name: "CommercialContractTermsVersion"
  has_one :acceptance, class_name: "CommercialContractAcceptance", foreign_key: :proposal_id, dependent: :restrict_with_error
  has_many :events, class_name: "CommercialContractEvent", foreign_key: :proposal_id, dependent: :destroy

  validates :public_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :title, :legal_business_name, :cnpj, :plan_name, presence: true
  validates :monthly_fee_cents, :setup_fee_cents, :minimum_term_months,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :representative_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :client_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :representative_name, :representative_cpf, :representative_role, :representative_email,
            presence: true, if: :requires_representative?
  validate :accepted_records_are_immutable, on: :update

  before_validation :ensure_token, on: :create
  before_validation :ensure_defaults
  before_validation :normalize_document_fields

  scope :ordered, -> { order(created_at: :desc) }

  def monthly_fee = monthly_fee_cents.to_i / 100.0
  def setup_fee = setup_fee_cents.to_i / 100.0
  def status_label = STATUS_LABELS.fetch(effective_status, status)
  def effective_status = expired? && !accepted? && !canceled? ? "expired" : status
  def accepted? = status == "accepted"
  def canceled? = status == "canceled"
  def expired? = expires_at.present? && expires_at < Time.current
  def editable? = !accepted? && !canceled?
  def requires_representative? = status.in?(%w[otp_pending accepted])

  def monthly_fee=(value)
    self.monthly_fee_cents = parse_money(value)
  end

  def setup_fee=(value)
    self.setup_fee_cents = parse_money(value)
  end

  def public_url(host:)
    Rails.application.routes.url_helpers.commercial_contract_proposal_url(public_token, host: host)
  end

  def mark_sent!(admin_user:, request:)
    update!(status: "sent", sent_at: Time.current) unless accepted? || canceled?
    log_event!("sent", admin_user:, request:)
  end

  def mark_viewed!(request:)
    return if accepted? || canceled?

    attrs = { viewed_at: viewed_at || Time.current, updated_at: Time.current }
    attrs[:status] = "viewed" if status.in?(%w[draft sent])
    update_columns(attrs)
    log_event!("viewed", request:)
  end

  def request_otp!(representative_params:, request:)
    raise ActiveRecord::RecordInvalid, self unless editable?

    assign_attributes(representative_params)
    self.status = "otp_pending"
    self.otp_sent_at = Time.current
    self.otp_expires_at = 15.minutes.from_now
    self.otp_attempts = 0
    code = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
    self.otp_digest = self.class.otp_digest_for(code, public_token)
    save!
    log_event!("otp_requested", request:, metadata: { representative_email: representative_email })
    code
  end

  def accept_with_otp!(otp_code:, request:)
    return false unless editable?
    return false unless otp_valid?(otp_code)

    accepted = nil
    transaction do
      accepted_at = Time.current
      proposal_hash = Digest::SHA256.hexdigest(contract_snapshot_payload)
      accepted = create_acceptance!(
        tenant: tenant,
        terms_version: terms_version,
        legal_business_name: legal_business_name,
        cnpj: cnpj,
        representative_name: representative_name,
        representative_cpf: representative_cpf,
        representative_role: representative_role,
        representative_email: representative_email,
        representative_phone: representative_phone,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        terms_hash: terms_version.document_hash,
        proposal_hash: proposal_hash,
        otp_confirmation_hash: Digest::SHA256.hexdigest("#{otp_digest}:#{accepted_at.to_i}"),
        accepted_at: accepted_at,
        evidence: evidence_payload(request:, proposal_hash:)
      )
      update!(
        status: "accepted",
        accepted_at: accepted_at,
        otp_digest: nil,
        otp_expires_at: nil
      )
      accepted.attach_final_documents!
      log_event!("accepted", request:, metadata: { acceptance_token: accepted.acceptance_token })
      log_event!("pdf_generated", request:, metadata: { acceptance_token: accepted.acceptance_token })
    end
    true
  end

  def register_failed_otp!(request:)
    increment!(:otp_attempts)
    log_event!("otp_failed", request:, metadata: { attempts: otp_attempts })
  end

  def otp_valid?(code)
    return false if otp_digest.blank? || otp_expires_at.blank? || otp_expires_at < Time.current
    return false if otp_attempts.to_i >= 5

    expected = self.class.otp_digest_for(code.to_s.gsub(/\D/, ""), public_token)
    ActiveSupport::SecurityUtils.secure_compare(expected, otp_digest)
  end

  def log_event!(event_type, admin_user: nil, request: nil, metadata: {})
    events.create!(
      tenant: tenant,
      admin_user: admin_user,
      event_type: event_type,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent,
      metadata: metadata.compact
    )
  end

  def self.otp_digest_for(code, token)
    Digest::SHA256.hexdigest("#{token}:#{code}:#{Rails.application.secret_key_base}")
  end

  def contract_snapshot_payload
    {
      token: public_token,
      tenant_id: tenant_id,
      legal_business_name: legal_business_name,
      cnpj: cnpj,
      plan_name: plan_name,
      monthly_fee_cents: monthly_fee_cents,
      setup_fee_cents: setup_fee_cents,
      minimum_term_months: minimum_term_months,
      starts_on: starts_on,
      scope_summary: scope_summary,
      billing_notes: billing_notes,
      external_costs_note: external_costs_note,
      terms_version: terms_version.version,
      terms_hash: terms_version.document_hash
    }.to_json
  end

  private

  def ensure_token
    return if public_token.present?

    loop do
      candidate = "P-#{Time.current.year}-#{SecureRandom.alphanumeric(6).upcase}"
      break self.public_token = candidate unless self.class.exists?(public_token: candidate)
    end
  end

  def ensure_defaults
    self.terms_version ||= CommercialContractTermsVersion.current_for(tenant) if tenant.present?
    self.title = "Contratação Unitymob" if title.blank?
    self.plan_name = "Unitymob completo" if plan_name.blank?
    self.scope_summary = DEFAULT_SCOPE if scope_summary.blank?
    self.external_costs_note = DEFAULT_EXTERNAL_COSTS if external_costs_note.blank?
    self.expires_at ||= 10.days.from_now
  end

  def normalize_document_fields
    self.cnpj = cnpj.to_s.gsub(/\D/, "") if cnpj.present?
    self.client_phone = client_phone.to_s.gsub(/\D/, "") if client_phone.present?
    self.representative_cpf = representative_cpf.to_s.gsub(/\D/, "") if representative_cpf.present?
    self.representative_phone = representative_phone.to_s.gsub(/\D/, "") if representative_phone.present?
    self.client_email = client_email.to_s.strip.downcase.presence
    self.representative_email = representative_email.to_s.strip.downcase.presence
  end

  def parse_money(value)
    return 0 if value.blank?

    digits = value.to_s.gsub(/[^\d,\.]/, "")
    digits = digits.delete(".").tr(",", ".") if digits.include?(",")
    (digits.to_f * 100).round
  end

  def accepted_records_are_immutable
    return unless accepted_at_was.present? || status_was == "accepted"

    allowed = %w[updated_at]
    changed = changes.keys - allowed
    errors.add(:base, "Contrato aceito não pode ser alterado.") if changed.any?
  end

  def evidence_payload(request:, proposal_hash:)
    {
      proposal_token: public_token,
      proposal_hash: proposal_hash,
      terms_version: terms_version.version,
      terms_hash: terms_version.document_hash,
      otp_sent_at: otp_sent_at&.iso8601,
      otp_confirmed_at: Time.current.iso8601,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      accepted_capability_statement: true,
      electronic_acceptance_clause: true
    }
  end
end
