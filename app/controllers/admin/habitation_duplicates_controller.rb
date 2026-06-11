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
        comparison: params[:comparison],
        ignored_id: params[:ignored_id]
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

    def match_payload(habitation)
      {
        id: habitation.id,
        codigo: habitation.codigo,
        title: habitation.titulo_anuncio.presence || habitation.display_title,
        status: habitation.intake_status_label.presence || habitation.status,
        broker: habitation.admin_user&.name || habitation.corretor_nome,
        edit_url: edit_admin_habitation_path(habitation)
      }
    end
  end
end
