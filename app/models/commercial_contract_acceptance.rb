class CommercialContractAcceptance < ApplicationRecord
  belongs_to :tenant
  belongs_to :proposal, class_name: "CommercialContractProposal", foreign_key: :proposal_id
  belongs_to :terms_version, class_name: "CommercialContractTermsVersion"

  has_one_attached :contract_pdf
  has_one_attached :certificate_pdf

  validates :acceptance_token, presence: true, uniqueness: true
  validates :legal_business_name, :cnpj, :representative_name, :representative_cpf,
            :representative_role, :representative_email, :terms_hash, :proposal_hash,
            :otp_confirmation_hash, :accepted_at, presence: true
  validates :proposal_id, uniqueness: true

  before_validation :ensure_token, on: :create

  def attach_final_documents!
    contract_data = CommercialContracts::PdfBuilder.new(proposal, acceptance: self, kind: :contract).render
    certificate_data = CommercialContracts::PdfBuilder.new(proposal, acceptance: self, kind: :certificate).render

    contract_pdf.attach(
      io: StringIO.new(contract_data),
      filename: "contrato-unitymob-#{proposal.public_token}.pdf",
      content_type: "application/pdf"
    )
    certificate_pdf.attach(
      io: StringIO.new(certificate_data),
      filename: "certificado-aceite-#{acceptance_token}.pdf",
      content_type: "application/pdf"
    )
  end

  private

  def ensure_token
    return if acceptance_token.present?

    loop do
      candidate = "A-#{SecureRandom.alphanumeric(12).upcase}"
      break self.acceptance_token = candidate unless self.class.exists?(acceptance_token: candidate)
    end
  end
end
