class Admin::HabitationAvailabilityBlocksController < Admin::BaseController
  requires_permission :edit, :imoveis
  before_action :set_habitation

  def index
    load_calendar
    @block = @habitation.availability_blocks.new
  end

  def create
    @block = @habitation.availability_blocks.new(block_params.merge(tenant: current_tenant))
    @block.save!
    redirect_to admin_habitation_availability_blocks_path(@habitation.id, month: @block.starts_on.strftime("%Y-%m")), notice: "Período bloqueado."
  rescue ActiveRecord::RecordInvalid
    load_calendar
    render :index, status: :unprocessable_entity
  end

  def destroy
    @habitation.availability_blocks.where(tenant: current_tenant).find(params[:id]).destroy!
    redirect_to admin_habitation_availability_blocks_path(@habitation.id, month: params[:month]), notice: "Período liberado."
  end

  private

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
