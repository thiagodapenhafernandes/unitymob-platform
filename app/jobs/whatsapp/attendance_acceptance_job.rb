module Whatsapp
  # Dono não abriu/respondeu dentro do pocket da regra: passa para outro do pool.
  class AttendanceAcceptanceJob < ApplicationJob
    queue_as :default

    def perform(attendance_id, expected_admin_user_id, tenant_id:)
      attendance = WhatsappAttendance.find_by(id: attendance_id, tenant_id: tenant_id)
      return unless attendance&.open? && !attendance.accepted? && attendance.admin_user_id == expected_admin_user_id

      Current.set(tenant: attendance.tenant) { Whatsapp::AttendanceManager.reassign!(attendance, reason: "not_accepted") }
    end
  end
end
