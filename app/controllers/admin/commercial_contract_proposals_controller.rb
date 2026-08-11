class Admin::CommercialContractProposalsController < Admin::BaseController
  before_action :require_admin_or_administrative_user!
  before_action :set_proposal, only: [:show, :edit, :update, :send_proposal, :cancel, :proposal_pdf, :contract_pdf, :certificate_pdf, :destroy]

  def index
    @status = params[:status].to_s.presence
    @proposals = current_tenant.commercial_contract_proposals.includes(:admin_user, :acceptance).ordered
    @proposals = @proposals.where(status: @status) if @status.in?(CommercialContractProposal::STATUSES)
    @counts = current_tenant.commercial_contract_proposals.group(:status).count
  end

  def show
    @events = @proposal.events.includes(:admin_user).ordered
  end

  def new
    @proposal = current_tenant.commercial_contract_proposals.new(
      admin_user: current_admin_user,
      terms_version: CommercialContractTermsVersion.current_for(current_tenant)
    )
  end

  def create
    @proposal = current_tenant.commercial_contract_proposals.new(proposal_params)
    @proposal.admin_user = current_admin_user
    assign_terms_version(@proposal)

    if @proposal.save
      @proposal.log_event!("created", admin_user: current_admin_user, request: request)
      redirect_to admin_commercial_contract_proposal_path(@proposal), notice: "Proposta criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    redirect_to admin_commercial_contract_proposal_path(@proposal), alert: "Contrato aceito não pode ser alterado." unless @proposal.editable?
  end

  def update
    assign_terms_version(@proposal)
    if @proposal.update(proposal_params)
      @proposal.log_event!("updated", admin_user: current_admin_user, request: request)
      redirect_to admin_commercial_contract_proposal_path(@proposal), notice: "Proposta atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def send_proposal
    @proposal.mark_sent!(admin_user: current_admin_user, request: request)
    redirect_to admin_commercial_contract_proposal_path(@proposal),
                notice: "Proposta marcada como enviada. Link público: #{commercial_contract_proposal_url(@proposal.public_token)}"
  end

  def cancel
    if @proposal.accepted?
      redirect_to admin_commercial_contract_proposal_path(@proposal), alert: "Contrato aceito não pode ser cancelado por aqui."
    else
      @proposal.update!(status: "canceled", canceled_at: Time.current)
      @proposal.log_event!("canceled", admin_user: current_admin_user, request: request)
      redirect_to admin_commercial_contract_proposal_path(@proposal), notice: "Proposta cancelada."
    end
  end

  def proposal_pdf
    pdf = CommercialContracts::PdfBuilder.new(@proposal, kind: :contract).render
    send_data pdf,
              filename: "proposta-unitymob-#{@proposal.public_token}.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  def contract_pdf
    pdf = @proposal.acceptance&.contract_pdf
    return redirect_to admin_commercial_contract_proposal_path(@proposal), alert: "Contrato final ainda não foi gerado." unless pdf&.attached?

    redirect_to rails_blob_path(pdf, disposition: "inline")
  end

  def certificate_pdf
    pdf = @proposal.acceptance&.certificate_pdf
    return redirect_to admin_commercial_contract_proposal_path(@proposal), alert: "Certificado ainda não foi gerado." unless pdf&.attached?

    redirect_to rails_blob_path(pdf, disposition: "inline")
  end

  def destroy
    if @proposal.accepted?
      redirect_to admin_commercial_contract_proposal_path(@proposal), alert: "Contrato aceito não pode ser removido."
    else
      @proposal.destroy
      redirect_to admin_commercial_contract_proposals_path, notice: "Proposta removida."
    end
  end

  private

  def set_proposal
    @proposal = current_tenant.commercial_contract_proposals.find(params[:id])
  end

  def proposal_params
    params.require(:commercial_contract_proposal).permit(
      :title,
      :legal_business_name,
      :trade_name,
      :cnpj,
      :client_email,
      :client_phone,
      :plan_name,
      :monthly_fee,
      :setup_fee,
      :minimum_term_months,
      :starts_on,
      :expires_at,
      :scope_summary,
      :billing_notes,
      :external_costs_note
    )
  end

  def assign_terms_version(proposal)
    requested_id = params.dig(:commercial_contract_proposal, :terms_version_id).presence
    proposal.terms_version =
      if requested_id
        current_tenant.commercial_contract_terms_versions.find(requested_id)
      else
        proposal.terms_version || CommercialContractTermsVersion.current_for(current_tenant)
      end
  end
end
