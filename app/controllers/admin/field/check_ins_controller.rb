# frozen_string_literal: true

module Admin
  module Field
    class CheckInsController < Admin::BaseController
      before_action :require_admin!, only: [:force_check_out]
      before_action :set_check_in, only: [:show, :force_check_out]

      def index
        @active_check_ins = CheckIn.where(status: :active).includes(:admin_user, :store).order(checked_in_at: :desc)
        @today_closed = CheckIn.where.not(status: :active).today.includes(:admin_user, :store).order(checked_in_at: :desc)
      end

      def show
      end

      def force_check_out
        result = CheckIns::CheckOutService.new(
          check_in: @check_in,
          reason: :closed_admin_force,
          actor: current_admin_user,
          ip: request.remote_ip
        ).call

        if result[:success]
          redirect_to admin_field_check_ins_path, notice: "Check-out forçado."
        else
          redirect_to admin_field_check_ins_path, alert: "Falha: #{result[:message]}"
        end
      end

      private

      def set_check_in
        @check_in = CheckIn.find(params[:id])
      end
    end
  end
end
