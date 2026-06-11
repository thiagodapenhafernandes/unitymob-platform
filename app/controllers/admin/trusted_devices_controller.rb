class Admin::TrustedDevicesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :access_security) }
  before_action :set_device

  def update
    case params[:status].to_s
    when "trusted"
      @device.trust!(current_admin_user)
      notice = "Aparelho aprovado."
    when "blocked"
      @device.block!(current_admin_user)
      notice = "Aparelho bloqueado."
    when "pending"
      @device.update!(status: "pending", trusted_at: nil, created_by: current_admin_user)
      notice = "Aparelho voltou para pendente."
    else
      return redirect_to admin_access_security_path, alert: "Status inválido."
    end

    redirect_to admin_access_security_path(anchor: "devices"), notice: notice
  end

  def destroy
    @device.destroy
    redirect_to admin_access_security_path(anchor: "devices"), notice: "Aparelho removido."
  end

  private

  def set_device
    @device = TrustedDevice.find(params[:id])
  end
end
