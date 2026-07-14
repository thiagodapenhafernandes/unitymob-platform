module Field
  class PropertySearchesController < BaseController
    before_action :load_setting
    before_action :authorize_ai_property_search!

    def show
      @page_title = "Busca inteligente de imóveis"
    end

    def create
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      transcription = search_text
      interpretation = interpreted_request(transcription)
      contextual = Ai::PropertySearch::ContextualFilters.new(
        setting: @setting,
        text: transcription,
        current_filters: parsed_current_filters,
        interpreted_filters: interpretation.filters
      ).call

      location_resolution = Ai::PropertySearch::LocationResolver.new(
        tenant: current_tenant,
        setting: @setting,
        filters: contextual.filters
      ).call

      development_resolution = Ai::PropertySearch::DevelopmentResolver.new(
        tenant: current_tenant,
        setting: @setting,
        filters: location_resolution.filters
      ).call
      interpreted_filters = development_resolution.filters

      query_result = Ai::PropertySearch::DataSource.call(
        tenant: current_tenant,
        admin_user: current_admin_user,
        setting: @setting,
        filters: interpreted_filters,
        sort: params[:sort],
        allow_flexible: false
      )
      presenter = Ai::PropertySearch::ResultPresenter.new(@setting)
      results = query_result.records.map { |habitation| presenter.call(habitation) }
      suggestion = if results.empty? && suggestions_enabled?
        Ai::PropertySearch::SuggestionFinder.new(
          tenant: current_tenant,
          admin_user: current_admin_user,
          setting: @setting,
          filters: interpreted_filters,
          sort: params[:sort]
        ).call
      end
      suggestions = Array(suggestion&.records).map { |habitation| presenter.call(habitation) }
      history_filters = suggestions.any? ? suggestion.filters : query_result.applied_filters
      history = record_history(
        transcription:,
        filters: history_filters,
        result_count: results.size + suggestions.size,
        status: "completed",
        started_at:
      )

      render json: {
        status: "completed",
        transcription:,
        filters: query_result.applied_filters,
        search_mode: contextual.mode,
        flexible: query_result.flexible,
        match_quality: results.any? ? "exact" : (suggestions.any? ? "approximate" : "none"),
        results:,
        suggestions:,
        suggestion_message: suggestion&.message,
        relaxed_criteria: suggestion&.relaxed || [],
        relaxed_labels: relaxed_labels(suggestion),
        location_corrections: location_resolution.corrections,
        history_id: history&.id,
        no_results_message: @setting.ai_property_search_no_results_message
      }
    rescue ArgumentError, Ai::PropertySearch::DataSource::UnsupportedSource => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("[ai property search] tenant=#{current_tenant&.id} user=#{current_admin_user&.id} error=#{e.class}: #{e.message}")
      record_failure(e, started_at) if defined?(started_at) && started_at
      render json: { error: "Não foi possível interpretar a busca agora. Tente novamente." }, status: :bad_gateway
    end

    def select
      history = AiPropertySearchHistory.where(tenant: current_tenant, admin_user: current_admin_user).find(params[:history_id])
      result = Ai::PropertySearch::DataSource.call(
        tenant: current_tenant,
        admin_user: current_admin_user,
        setting: @setting,
        filters: history.interpreted_filters
      )
      habitation = result.records.find { |record| record.id == params[:habitation_id].to_i }
      raise ActiveRecord::RecordNotFound unless habitation

      history.update!(selected_habitation: habitation)
      head :no_content
    end

    RELAXED_CRITERIA_LABELS = {
      "amenities" => "Sem exigir todas as características",
      "development" => "Sem filtro de empreendimento",
      "neighborhood" => "Bairro ampliado para a cidade",
      "quantities" => "Quartos/suítes/vagas com 1 a menos",
      "price" => "Preço até %{tolerance}%% além da faixa"
    }.freeze

    private

    def load_setting
      @setting = PropertySetting.instance(tenant: current_tenant)
    end

    def suggestions_enabled?
      @setting.ai_property_search_allow_flexible_results? ||
        (@setting.respond_to?(:ai_property_search_resilient_search_enabled?) && @setting.ai_property_search_resilient_search_enabled?)
    end

    def relaxed_labels(suggestion)
      tolerance = @setting.ai_property_search_price_tolerance_percentage.to_i
      Array(suggestion&.relaxed).filter_map do |key|
        label = RELAXED_CRITERIA_LABELS[key]
        next unless label

        format(label, tolerance: tolerance)
      end
    end

    def authorize_ai_property_search!
      return if @setting.ai_property_search_available_to?(current_admin_user)

      respond_to do |format|
        format.html { redirect_to field_root_path, alert: "Busca inteligente indisponível para seu perfil." }
        format.json { render json: { error: "Busca inteligente indisponível para seu perfil." }, status: :forbidden }
      end
    end

    def search_text
      if params[:audio].present?
        duration = Float(params[:audio_duration_seconds], exception: false)
        max_duration = @setting.ai_property_search_max_audio_duration_seconds
        raise ArgumentError, "Não foi possível validar a duração do áudio." unless duration
        raise ArgumentError, "O áudio ultrapassa o limite de #{max_duration} segundos." if duration > max_duration

        Ai::PropertySearch::Transcriber.new(setting: @setting, audio: params[:audio]).call
      else
        params[:query].to_s.strip.first(2_000)
      end
    end

    def interpreted_request(transcription)
      if confirmed?
        filters = JSON.parse(params[:filters].to_s)
        normalized = Ai::PropertySearch::FilterContract.new(@setting).normalize(filters)
        Ai::PropertySearch::Interpreter::Result.new(
          intent: "search_properties",
          filters: normalized,
          missing_required_information: [],
          clarifying_question: nil
        )
      else
        Ai::PropertySearch::Interpreter.new(
          setting: @setting,
          text: transcription,
          current_filters: parsed_current_filters
        ).call
      end
    rescue JSON::ParserError
      raise ArgumentError, "Os filtros confirmados são inválidos."
    end

    def confirmed?
      ActiveModel::Type::Boolean.new.cast(params[:confirmed])
    end

    def parsed_current_filters
      JSON.parse(params[:current_filters].presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def record_history(transcription:, filters:, result_count:, status:, started_at:, error_message: nil)
      return unless @setting.ai_property_search_history_enabled?

      history = AiPropertySearchHistory.create!(
        tenant: current_tenant,
        admin_user: current_admin_user,
        original_audio_reference: nil,
        transcription: transcription.to_s.first(10_000),
        interpreted_filters: filters,
        result_count:,
        processing_time_ms: elapsed_ms(started_at),
        status:,
        error_message: error_message.to_s.first(1_000).presence
      )
      AiPropertySearchHistoryCleanupJob.perform_later(current_tenant.id)
      history
    end

    def record_failure(error, started_at)
      record_history(
        transcription: params[:query].to_s,
        filters: {},
        result_count: 0,
        status: "failed",
        started_at:,
        error_message: "#{error.class}: #{error.message}"
      )
    rescue StandardError => history_error
      Rails.logger.warn("[ai property search history] #{history_error.class}: #{history_error.message}")
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
    end
  end
end
