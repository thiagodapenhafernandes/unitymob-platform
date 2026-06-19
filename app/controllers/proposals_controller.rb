class ProposalsController < ApplicationController
  layout "proposal"
  before_action :set_proposal
  before_action :noindex

  # Página pública da proposta — /p/:token
  def show
    @proposal.mark_viewed!
    @habitation = @proposal.habitation
  end

  # Cliente aceita ou recusa — /p/:token/decidir
  def decide
    if @proposal.responded_at.blank? && !@proposal.expired?
      @proposal.decide!(params[:decision])
    end
    redirect_to public_proposal_path(@proposal.public_token)
  end

  private

  def set_proposal
    @proposal = Proposal.find_by!(public_token: params[:token])
  end

  def noindex
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end
end
