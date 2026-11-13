class Admin::ImovelwebLeadReceiptsController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :set_connection

  def index
    @receipts = @connection.imovelweb_lead_receipts
    @receipts = @receipts.where(status: params[:status]) if %w[pending processed quarantined].include?(params[:status])
    @receipts = @receipts.order(received_at: :desc, id: :desc).paginate(page: params[:page], per_page: 25)
  end

  def show
    @receipt = @connection.imovelweb_lead_receipts.find(params[:id])
    @entry = JSON.parse(@receipt.payload)
  end

  private

  def set_connection
    @connection = ImovelwebConnection.where(tenant: current_tenant).find(params[:imovelweb_connection_id])
  end
end
