# frozen_string_literal: true

# Pedido de check-in manual — quando GPS não funciona, corretor envia
# justificativa e aguarda aprovação do admin.
module Field
  class ManualCheckinRequestsController < BaseController
    before_action :ensure_field_enabled!
    before_action :ensure_field_agent!

    def new
      @request = ManualCheckinRequest.new
      @stores = Store.active.order(:name)
    end

    def create
      @request = ManualCheckinRequest.new(
        admin_user: current_admin_user,
        store_id: params.dig(:manual_checkin_request, :store_id),
        justification: params.dig(:manual_checkin_request, :justification),
        status: :pending
      )

      if @request.save
        CheckinAuditLog.log!(
          action: "manual_request_created",
          admin_user: current_admin_user,
          ip: request.remote_ip,
          metadata: { request_id: @request.id, store_id: @request.store_id }
        )
        redirect_to field_root_path, notice: "Solicitação enviada. Aguarde a aprovação do administrador."
      else
        @stores = Store.active.order(:name)
        render :new, status: :unprocessable_entity
      end
    end
  end
end
