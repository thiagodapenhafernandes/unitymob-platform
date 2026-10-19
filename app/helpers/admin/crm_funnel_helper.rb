module Admin::CrmFunnelHelper
  def crm_funnel_rows(funnel)
    labels = { leads: "Leads", qualified: "Qualificados", visited: "Com visita realizada", proposed: "Com proposta enviada", won: "Ganhos no CRM" }
    labels.map do |key, label|
      count = funnel.fetch(:counts).fetch(key)
      total = funnel.fetch(:counts).fetch(:leads)
      { label: label, count: count, share: total.positive? ? number_to_percentage(100.0 * count / total, precision: 1) : "—" }
    end
  end

  def ga4_report_status_label(status)
    {
      ok: "Relatório consultado", stale: "Última leitura disponível; consulta atual falhou",
      not_configured: "Conexão de leitura ainda não configurada", unavailable: "Consulta indisponível; confira acesso e API",
      restricted: "Relatório da propriedade disponível ao titular da conta",
      filtered: "Remova os filtros de corretor e modalidade para consultar o total da propriedade"
    }.fetch(status.to_sym)
  end

  def ga4_event_label(name)
    {
      "generate_lead" => "Lead confirmado", "qualify_lead" => "Qualificação",
      "visit_completed" => "Visita realizada", "proposal_sent" => "Proposta enviada", "close_convert_lead" => "Ganho declarado"
    }.fetch(name)
  end
end
