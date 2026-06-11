# frozen_string_literal: true

# Health-check simples da feature de campo. Retorna 404 com flag off,
# 200 com flag on. Usado pra confirmar que o gate está funcionando sem
# expor nenhum endpoint funcional ainda.
module Field
  class HealthController < ApplicationController
    include FieldFeatureGate
    before_action :ensure_field_enabled!

    def up
      render json: { status: "ok", feature: "field_checkin", enabled: true }
    end
  end
end
