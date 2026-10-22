class Admin::HabitationAvailabilityBlocksController < Admin::BaseController
  requires_permission :edit, :imoveis
  before_action :set_habitation

  def index
    load_calendar
    @block = @habitation.availability_blocks.new
    if params[:calendar] == "1"
      render partial: "calendar", layout: false
    elsif modal_request?
      render partial: "modal_content", layout: false
    end
  end

  def create
    @block = @habitation.availability_blocks.new(block_params.merge(tenant: current_tenant))
    @block.save!
    redirect_to calendar_location(@block.starts_on.strftime("%Y-%m")), status: (modal_request? ? :see_other : :found), notice: "Período bloqueado."
  rescue ActiveRecord::RecordInvalid
    load_calendar
    if modal_request?
      render partial: "modal_content", layout: false, status: :unprocessable_entity
    else
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @habitation.availability_blocks.where(tenant: current_tenant).find(params[:id]).destroy!
    redirect_to calendar_location(params[:month]), status: (modal_request? ? :see_other : :found), notice: "Período liberado."
  end

  private

  def modal_request?
    params[:modal] == "1"
  end

  def calendar_location(month)
    admin_habitation_availability_blocks_path(@habitation.id, month: month, modal: ("1" if modal_request?))
  end

  def set_habitation
    @habitation = current_tenant.habitations.find(params[:habitation_id])
    return head :not_found unless @habitation.daily_rental?
    return if helpers.admin_can_edit_habitation?(@habitation)

    head :forbidden
  end

  def load_calendar
    @month = helpers.rental_availability_month(params[:month])
    @blocks = @habitation.availability_blocks.where(tenant: current_tenant).overlapping(@month, @month.end_of_month).order(:starts_on).to_a
  end

  def block_params
    params.require(:habitation_availability_block).permit(:starts_on, :ends_on)
  end
end
