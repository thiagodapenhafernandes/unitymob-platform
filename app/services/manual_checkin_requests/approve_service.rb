module ManualCheckinRequests
  # Aprova um pedido manual criando um CheckIn sem validação de GPS/turno.
  # O check-in criado fica marcado com device_info: { manual: true } para distinguir.
  class ApproveService
    def initialize(request:, reviewer:, notes: nil)
      @request = request
      @reviewer = reviewer
      @notes = notes
    end

    def call
      return { success: false, error: :invalid_state } unless @request.pending?
      return { success: false, error: :already_has_active } if @request.admin_user.active_check_in.present?

      check_in = CheckIn.new(
        tenant: @request.tenant,
        admin_user: @request.admin_user,
        store: @request.store,
        checked_in_at: Time.current,
        status: :active,
        device_info: { manual: true, approved_by: @reviewer&.id, notes: @notes }
      )

      ApplicationRecord.transaction do
        check_in.save!
        @request.update!(
          status: :approved,
          reviewed_by_admin_user: @reviewer,
          reviewed_at: Time.current,
          review_notes: @notes,
          approved_check_in: check_in
        )

        CheckinAuditLog.log!(
          action: "manual_request_approved",
          check_in: check_in,
          actor: @reviewer,
          metadata: { request_id: @request.id, justification: @request.justification }
        )
      end

      { success: true, check_in: check_in }
    end
  end
end
