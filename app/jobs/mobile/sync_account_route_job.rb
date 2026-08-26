# frozen_string_literal: true

module Mobile
  # Mantém o gateway de discovery do app híbrido em dia sozinho — disparado
  # pelo AdminUser em vez de exigir cadastro manual por corretor.
  class SyncAccountRouteJob < ApplicationJob
    queue_as :default

    def perform(admin_user_id)
      admin_user = AdminUser.find_by(id: admin_user_id)
      return if admin_user.blank?

      Mobile::AccountRouteRegistrar.sync!(admin_user)
    end
  end
end
