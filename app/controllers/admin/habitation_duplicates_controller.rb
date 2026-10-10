module Admin
  class HabitationDuplicatesController < Admin::BaseController
    before_action :authorize_duplicate_check!

    def check
      result = HabitationDuplicateChecker.new(
        street: params[:street],
        number: params[:number],
        building: params[:building],
        unit: params[:unit],
        status: params[:status],
        complement: params[:complement],
        category: params[:category],
        lot: params[:lot],
        block_section: params[:block_section],
        development_code: params[:development_code],
        comparison: params[:comparison],
        ignored_id: params[:ignored_id],
        tenant: Current.tenant,
        owner_ids: duplicate_check_owner_ids
      ).call

      render json: {
        complete: result.complete,
        duplicate: result.duplicate?,
        comparison: result.comparison,
        matches: result.matches.first(5).map { |habitation| match_payload(habitation) }
      }
    end

    private

    def authorize_duplicate_check!
      return if can?(:view, :imoveis) || can?(:view, :captacoes)

      render json: { error: "forbidden" }, status: :forbidden
    end

    # A checagem mistura imóveis e captações, então só entram donos
    # acessíveis nos dois recursos (interseção). nil = escopo total
    # em ambos (sem filtro).
    def duplicate_check_owner_ids
      imoveis_ids = accessible_owner_ids(:imoveis)
      captacoes_ids = accessible_owner_ids(:captacoes)
      return nil if imoveis_ids.nil? && captacoes_ids.nil?
      return captacoes_ids if imoveis_ids.nil?
      return imoveis_ids if captacoes_ids.nil?

      imoveis_ids & captacoes_ids
    end

    def match_payload(habitation)
      {
        id: habitation.id,
        codigo: habitation.codigo,
        title: habitation.titulo_anuncio.presence || habitation.display_title,
        status: habitation.intake_status_label.presence || habitation.status,
        broker: habitation.admin_user&.name || habitation.corretor_nome,
        edit_url: edit_admin_habitation_path(habitation.id)
      }
    end
  end
end
