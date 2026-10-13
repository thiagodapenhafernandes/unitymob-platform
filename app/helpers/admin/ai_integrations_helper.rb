module Admin::AiIntegrationsHelper
  def ai_batch_status_label(status)
    { "idle" => "Nenhum lote iniciado", "processing" => "Em processamento", "completed" => "Concluído", "failed" => "Falha na geração" }.fetch(status.to_s, "Status indisponível")
  end
end
