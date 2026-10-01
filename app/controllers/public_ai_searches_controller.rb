# Busca por descrição/voz do hero da home. Responde só com a URL da listagem (filtros já traduzidos).
class PublicAiSearchesController < ApplicationController
  def create
    home_setting = HomeSetting.find_by(tenant_id: public_tenant.id)
    return render_error("Busca por descrição indisponível.", :not_found) unless home_setting&.hero_ai_search_available?

    result = Ai::PropertySearch::PublicQuery.new(
      tenant: public_tenant,
      text: params[:query],
      audio: params[:audio],
      audio_duration: params[:audio_duration_seconds],
      default_transaction: params[:transaction_type]
    ).call

    Rails.logger.info("[public ai search] tenant=#{public_tenant.id} mode=#{params[:audio].present? ? "voice" : "text"} filters=#{result.params.keys.join(",")}")
    render json: {
      redirect_url: habitations_path(result.params.merge("v" => "2")),
      summary: result.summary,
      transcription: result.transcription
    }
  rescue Ai::PropertySearch::PublicQuery::Unavailable => e
    render_error(e.message, :not_found)
  rescue ArgumentError => e
    render_error(e.message, :unprocessable_entity)
  rescue StandardError => e
    Rails.logger.error("[public ai search] tenant=#{public_tenant&.id} error=#{e.class}")
    render_error("Não foi possível interpretar a busca agora. Tente novamente ou use os filtros.", :bad_gateway)
  end

  private

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
