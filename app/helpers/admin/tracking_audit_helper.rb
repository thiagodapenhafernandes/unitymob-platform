module Admin::TrackingAuditHelper
  TRANSPORT_LABELS = { "site" => "Site", "webhook" => "Webhook", "google_webhook" => "Google via webhook", "ga4" => "GA4", "meta" => "Meta" }.freeze
  STATUS_LABELS = {
    "pending" => ["Pendente", :amber], "sending" => ["Em envio", :amber],
    "browser_offered" => ["Oferecido ao navegador", :gray], "http_accepted" => ["HTTP aceito", :blue],
    "received" => ["Recebido pela plataforma", :green], "failed" => ["Falhou", :red],
    "rejected" => ["Rejeitado", :red], "uncertain" => ["Sem confirmação", :amber],
    "skipped" => ["Não enviado", :gray], "record_removed" => ["Registro de envio removido", :gray]
  }.freeze
  OCCURRENCE_LABELS = { "lead_created" => "Entrada do lead", "lead_updated" => "Alteração do lead",
    "appointment_updated" => "Alteração de agendamento", "proposal_updated" => "Alteração de proposta",
    "form_submitted" => "Formulário enviado" }.freeze
  REASON_LABELS = {
    "business_type_missing" => "Tipo de negócio ausente", "original_email_missing" => "E-mail original ausente",
    "original_identity_missing" => "Identificação original ausente", "identity_missing" => "Identificação insuficiente",
    "tenant_mismatch" => "Conta divergente", "destination_inactive" => "Destino inativo",
    "destination_changed" => "Destino alterado", "destination_blocked" => "Destino bloqueado",
    "receipt_unconfirmed" => "Recebimento não confirmado", "lead_ineligible" => "Lead não elegível",
    "config_inactive" => "Integração inativa", "before_activation" => "Evento anterior à ativação",
    "expired" => "Prazo de envio expirado", "future_event" => "Data do evento no futuro",
    "consent_missing" => "Consentimento ausente", "identity_changed" => "Identificação alterada"
  }.freeze

  def ax_tracking_delivery(link:)
    render "admin/shared/ui/tracking_delivery", link: link
  end

  def tracking_transport_label(transport)
    TRANSPORT_LABELS.fetch(transport, "Transporte desconhecido")
  end

  def tracking_status_badge(status)
    label, tone = STATUS_LABELS.fetch(status, ["Estado desconhecido", :gray])
    ax_badge(label, tone: tone)
  end

  def tracking_attempt_badge(link, attempt)
    status = attempt["status"].presence
    status ||= link.delivery_status if link.transport == "ga4"
    status ||= attempt["http_status"].to_i.between?(200, 299) ? "http_accepted" : "failed" if attempt["http_status"].present?
    status ||= "uncertain" if attempt["error_class"].present?
    tracking_status_badge(status)
  end

  def tracking_occurrence_label(name)
    OCCURRENCE_LABELS.fetch(name, "Evento registrado")
  end

  def tracking_reason_label(reason)
    REASON_LABELS.fetch(reason, "Motivo não catalogado")
  end

  def tracking_audit_time(value)
    return "Não registrada" if value.blank?

    l(value.is_a?(String) ? Time.iso8601(value) : value, format: "%d/%m/%Y %H:%M:%S")
  rescue ArgumentError
    "Data indisponível"
  end
end
