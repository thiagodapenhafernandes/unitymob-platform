module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_admin_user

    def connect
      self.current_admin_user = find_verified_admin_user
    end

    # Streams já abertos não re-autenticam sozinhos: derruba as conexões do
    # usuário em transferência, inativação e revogação individual de acesso.
    # Falha de infra do cable não quebra o chamador.
    def self.disconnect_admin_user(user)
      return if user.blank?

      ActionCable.server.remote_connections.where(current_admin_user: user).disconnect
    rescue => e
      Rails.logger.warn("[ApplicationCable] disconnect_admin_user: #{e.message}")
    end

    private

    def find_verified_admin_user
      # catch(:warden): os hooks de timeoutable/epoch fazem throw(:warden) ao
      # derrubar sessão — fora do Warden::Manager (aqui é thread do cable) isso
      # viraria UncaughtThrowError e o socket ficaria em loop de reconexão.
      user = catch(:warden) { env["warden"]&.user(:admin_user) }
      user.is_a?(AdminUser) && user.active? ? user : reject_unauthorized_connection
    end
  end
end
