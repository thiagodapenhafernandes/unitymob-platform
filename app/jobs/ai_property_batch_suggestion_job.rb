class AiPropertyBatchSuggestionJob < ApplicationJob
  queue_as :default

  def perform(triggered_by_id: nil)
    admin_user = AdminUser.find_by(id: triggered_by_id)
    scope = Habitation.order(:id)
    total = scope.count
    processed = 0
    failed = 0

    set_status!("processing", 0, "Gerando sugestões com IA para #{total} imóveis.")

    scope.find_each(batch_size: 25) do |habitation|
      Ai::PropertyContentService.new(habitation, admin_user: admin_user).generate_suggestion!
    rescue => e
      failed += 1
      Rails.logger.error("[AiPropertyBatchSuggestionJob] habitation=#{habitation.id} error=#{e.message}")
    ensure
      processed += 1
      progress = total.positive? ? ((processed.to_f / total) * 100).round : 100
      set_status!("processing", progress, "Processados #{processed}/#{total}. Falhas: #{failed}.")
    end

    set_status!("completed", 100, "Lote concluído. Processados #{processed}/#{total}. Falhas: #{failed}.")
  rescue => e
    set_status!("failed", Setting.get("openai_batch_progress", "0").to_i, "Falha no lote: #{e.message}")
    raise
  end

  private

  def set_status!(status, progress, message)
    Setting.set("openai_batch_status", status, "Status do enriquecimento em lote com IA")
    Setting.set("openai_batch_progress", progress.to_i.clamp(0, 100).to_s, "Progresso do enriquecimento em lote com IA")
    Setting.set("openai_batch_message", message.to_s, "Mensagem do enriquecimento em lote com IA")
    Setting.set("openai_batch_last_at", Time.current.iso8601, "Última atualização do enriquecimento em lote com IA")
  end
end
