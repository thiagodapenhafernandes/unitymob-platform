# frozen_string_literal: true

module Mobile
  # Contraparte de SyncAccountRouteJob para quando o AdminUser é destruído —
  # recebe o e-mail direto (não o id, que já não existe mais).
  class DeactivateAccountRouteJob < ApplicationJob
    queue_as :default

    def perform(email)
      Mobile::AccountRouteRegistrar.deactivate!(email)
    end
  end
end
