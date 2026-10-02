module Dashboard
  # Escopo único da "captação efetivada no período": captações de corretor
  # aprovadas (admin_approved/internal/published) pela data de aprovação/
  # liberação, recortadas por tipo (venda = valor_venda_cents > 0, locação =
  # valor_locacao_cents > 0). Fonte da verdade do dashboard de captações E
  # do drill-down na listagem de imóveis — os dois contam o mesmo conjunto.
  class CaptacaoScope
    EFFECTIVE_INTAKE_STATUSES = %w[admin_approved internal published].freeze
    KINDS = %w[venda locacao].freeze
    APPROVAL_TIMESTAMP_SQL = "COALESCE(habitations.admin_reviewed_at, habitations.broker_released_at)".freeze

    def self.call(tenant:, starts_at:, ends_at:, kind:, owner_ids: nil)
      raise ArgumentError, "kind inválido: #{kind.inspect}" unless KINDS.include?(kind.to_s)

      price_column = kind.to_s == "locacao" ? :valor_locacao_cents : :valor_venda_cents
      scope = tenant.habitations
                    .broker_intakes
                    .where(intake_status: EFFECTIVE_INTAKE_STATUSES)
                    .where("#{APPROVAL_TIMESTAMP_SQL} BETWEEN ? AND ?", starts_at.beginning_of_day, ends_at.end_of_day)
      scope = scope.where(admin_user_id: owner_ids) unless owner_ids.nil?
      scope.where("COALESCE(habitations.#{price_column}, 0) > 0")
    end
  end
end
