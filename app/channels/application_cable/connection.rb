module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_admin_user

    def connect
      self.current_admin_user = find_verified_admin_user
    end

    private

    def find_verified_admin_user
      env["warden"]&.user(:admin_user) || reject_unauthorized_connection
    end
  end
end
