class ManagementController < ApplicationController
  before_action :require_admin!, except: [:dashboard, :finance]
  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to management_path, alert: error.record.errors.full_messages.to_sentence
  end
  def finance
    head :forbidden unless current_staff.admin? || current_staff.role == "financeiro"
  end
  def dashboard
    return render :finance if current_staff.role == "financeiro"
    @dashboard = Support::OperationsDashboard.new(admin: current_staff.admin?)

  end
  def index
    @staffs = Staff.order(:name)
    @accounts = Support::Account.order(:name)
  end
  def create_staff
    staff = Staff.create!(params.require(:staff).permit(:name, :email, :role))
    @activation_url = activate_url(token: staff.activation_token!)
    index
    render :index
  end
  def update_staff
    staff = Staff.find(params[:id])
    return redirect_to(management_path, alert: "Outro administrador deve alterar seu acesso.") if staff == current_staff
    if params[:reset] == "1"
      @activation_url = activate_url(token: staff.activation_token!)
    else
      staff.update!(params.require(:staff).permit(:role, :active).merge(session_version: staff.session_version + 1))
    end
    Support::Account.find_each do |account|
      Support::Delivery.create!(account: account, payload: { kind: "revoke_access", operator_id: staff.id.to_s, issued_at: Time.current.iso8601(6) })
    end
    index
    render :index
  end
  def update_account
    account = Support::Account.find(params[:id])
    account.with_lock do
      account.update!(params.require(:account).permit(:name, :active).merge(control_revision: account.control_revision + 1))
      Support::Delivery.create!(account: account, payload: { kind: "account_state", active: account.active?, revision: account.control_revision })
    end
    redirect_to management_path, notice: "Conta atualizada."
  end
  private
  def require_admin!
    head :forbidden unless current_staff.admin?
  end
end
