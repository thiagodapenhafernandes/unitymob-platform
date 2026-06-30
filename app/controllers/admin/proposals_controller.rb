class Admin::ProposalsController < Admin::BaseController
  before_action -> { check_permission!(:view, :comercial) }, only: [:new, :edit, :pdf]
  before_action -> { check_permission!(:manage, :comercial) }, only: [:create, :update, :send_proposal, :destroy]
  before_action :set_lead, only: [:new, :create]
  before_action :set_proposal, only: [:edit, :update, :send_proposal, :pdf, :destroy]

  def new
    @proposal = @lead.proposals.new(
      habitation_id: @lead.property_id,
      admin_user: current_admin_user,
      validade: 7.days.from_now.to_date
    )
    @habitations = habitation_options
    @page_title = "Nova Proposta"
  end

  def create
    @proposal = @lead.proposals.new(proposal_params)
    @proposal.admin_user = current_admin_user
    @proposal.status = "rascunho"

    if @proposal.save
      LeadActivity.log!(lead: @lead, kind: "proposal_created", metadata: { proposal_id: @proposal.id })
      redirect_to admin_lead_path(@lead), notice: "Proposta criada. Envie o link ao cliente."
    else
      @habitations = habitation_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @lead = @proposal.lead
    @habitations = habitation_options
    @page_title = "Editar Proposta"
  end

  def update
    if @proposal.update(proposal_params)
      redirect_to admin_lead_path(@proposal.lead), notice: "Proposta atualizada."
    else
      @lead = @proposal.lead
      @habitations = habitation_options
      render :edit, status: :unprocessable_entity
    end
  end

  def send_proposal
    @proposal.mark_sent!
    redirect_to admin_lead_path(@proposal.lead), notice: "Proposta marcada como enviada. Link: #{public_proposal_url(@proposal.public_token)}"
  end

  def pdf
    pdf_data = Proposals::PdfBuilder.new(@proposal).render
    send_data pdf_data,
              filename: "proposta-#{@proposal.public_token}.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  def destroy
    lead = @proposal.lead
    @proposal.destroy
    redirect_to admin_lead_path(lead), notice: "Proposta removida."
  end

  private

  def set_lead
    @lead = current_tenant.leads.find(params[:lead_id])
  end

  def set_proposal
    @proposal = Proposal.joins(:lead).where(leads: { tenant_id: current_tenant.id }).find(params[:id])
  end

  def habitation_options
    current_tenant.habitations.order(updated_at: :desc).limit(500)
  end

  def proposal_params
    params.require(:proposal).permit(:habitation_id, :title, :valor, :entrada, :condicoes, :validade)
  end
end
