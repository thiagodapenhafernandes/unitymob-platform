module AdminUsers
  # Notificação ÚNICA ao corretor que recebe uma carteira (exclusão ou
  # inativação de outro usuário): totais agregados, nunca uma por item.
  class PortfolioReassignmentNotifier
    def self.call(target:, leads_count:, habitations_count:, from_user_name:)
      new(target:, leads_count:, habitations_count:, from_user_name:).call
    end

    def initialize(target:, leads_count:, habitations_count:, from_user_name:)
      @target = target
      @leads_count = leads_count.to_i
      @habitations_count = habitations_count.to_i
      @from_user_name = from_user_name.to_s
    end

    def call
      return nil if @target.blank? || (@leads_count.zero? && @habitations_count.zero?)

      InAppNotification.notify!(
        admin_user: @target,
        kind: "portfolio_reassigned",
        title: "Você recebeu uma carteira",
        body: "Foram atribuídos a você #{parts.join(' e ')}#{source_suffix}.",
        url: target_url,
        metadata: { leads_count: @leads_count, habitations_count: @habitations_count }
      )
    end

    private

    def parts
      parts = []
      parts << "#{@habitations_count} #{@habitations_count == 1 ? 'imóvel' : 'imóveis'}" if @habitations_count.positive?
      parts << "#{@leads_count} #{@leads_count == 1 ? 'lead' : 'leads'}" if @leads_count.positive?
      parts
    end

    def source_suffix
      @from_user_name.present? ? " (carteira de #{@from_user_name})" : ""
    end

    def target_url
      routes = Rails.application.routes.url_helpers
      return routes.admin_leads_path if @leads_count.positive?
      return routes.admin_habitations_path if @habitations_count.positive?

      nil
    end
  end
end
