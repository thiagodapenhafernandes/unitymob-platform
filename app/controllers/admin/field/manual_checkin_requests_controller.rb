# frozen_string_literal: true

module Admin
  module Field
    class ManualCheckinRequestsController < Admin::BaseController
      before_action -> { check_permission!(:view, :field_manual) }
      before_action -> { check_permission!(:manage, :field_manual) }, only: %i[approve reject]
      before_action :set_request, only: [:show, :approve, :reject]

      def index
        @pending = current_tenant.manual_checkin_requests.pending.recent.includes(:admin_user, :store)
        @resolved = current_tenant.manual_checkin_requests.where.not(status: :pending).recent.includes(:admin_user, :store).limit(50)
      end

      def show
      end

      def approve
        result = ManualCheckinRequests::ApproveService.new(
          request: @request,
          reviewer: current_admin_user,
          notes: params[:review_notes]
        ).call

        if result[:success]
          redirect_to admin_field_manual_checkin_requests_path, notice: "Solicitação aprovada."
        else
          redirect_to admin_field_manual_checkin_requests_path, alert: "Falha: #{result[:error]}"
        end
      end

      def reject
        @request.review!(reviewer: current_admin_user, approve: false, notes: params[:review_notes])
        CheckinAuditLog.log!(
          action: "manual_request_rejected",
          admin_user: @request.admin_user,
          actor: current_admin_user,
          metadata: { request_id: @request.id, notes: params[:review_notes] }
        )
        redirect_to admin_field_manual_checkin_requests_path, notice: "Solicitação rejeitada."
      end

      private

      def set_request
        @request = current_tenant.manual_checkin_requests.find(params[:id])
      end
    end
  end
end
