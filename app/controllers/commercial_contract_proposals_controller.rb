class CommercialContractProposalsController < ApplicationController
  layout "proposal"
  before_action :set_proposal
  before_action :noindex

  def show
    @proposal.mark_viewed!(request: request)
  end

  def request_otp
    if @proposal.expired? || @proposal.canceled? || @proposal.accepted?
      redirect_to commercial_contract_proposal_path(@proposal.public_token), alert: "Esta proposta não está disponível para aceite."
      return
    end
    unless params.dig(:commercial_contract_proposal, :authority_confirmed).to_s == "1"
      @proposal.assign_attributes(representative_params)
      @proposal.errors.add(:base, "Confirme que possui poderes para representar a empresa.")
      render :show, status: :unprocessable_entity
      return
    end

    code = @proposal.request_otp!(representative_params: representative_params, request: request)
    CommercialContractMailer.with(
      proposal: @proposal,
      code: code,
      acceptance_url: commercial_contract_proposal_url(@proposal.public_token)
    ).otp.deliver_now
    redirect_to commercial_contract_proposal_path(@proposal.public_token, step: "otp"),
                notice: "Enviamos o código para #{@proposal.representative_email}."
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_entity
  end

  def proposal_pdf
    pdf = CommercialContracts::PdfBuilder.new(@proposal, kind: :contract).render
    send_data pdf,
              filename: "proposta-unitymob-#{@proposal.public_token}.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  def accept
    if @proposal.accept_with_otp!(otp_code: params[:otp_code], request: request)
      redirect_to commercial_contract_proposal_path(@proposal.public_token), notice: "Contrato aceito com sucesso."
    else
      @proposal.register_failed_otp!(request: request)
      redirect_to commercial_contract_proposal_path(@proposal.public_token, step: "otp"), alert: "Código inválido ou expirado."
    end
  end

  def contract_pdf
    pdf = @proposal.acceptance&.contract_pdf
    return redirect_to commercial_contract_proposal_path(@proposal.public_token), alert: "Contrato final ainda não está disponível." unless pdf&.attached?

    redirect_to rails_blob_path(pdf, disposition: "inline")
  end

  def certificate_pdf
    pdf = @proposal.acceptance&.certificate_pdf
    return redirect_to commercial_contract_proposal_path(@proposal.public_token), alert: "Certificado ainda não está disponível." unless pdf&.attached?

    redirect_to rails_blob_path(pdf, disposition: "inline")
  end

  private

  def set_proposal
    @proposal = CommercialContractProposal.find_by!(public_token: params[:token])
    @layout_setting = LayoutSetting.instance(tenant: @proposal.tenant)
  end

  def noindex
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end

  def representative_params
    params.require(:commercial_contract_proposal).permit(
      :representative_name,
      :representative_cpf,
      :representative_role,
      :representative_email,
      :representative_phone
    )
  end
end
