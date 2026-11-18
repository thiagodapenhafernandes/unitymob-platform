require "rails_helper"

RSpec.describe Admin::TrackingAuditHelper, type: :helper do
  include Admin::UiHelper

  it "distingue a resposta HTTP da confirmação de recebimento e da incerteza" do
    link = instance_double(TrackingEventLink, transport: "google_webhook")
    expect(helper.tracking_attempt_badge(link, { "http_status" => 204 })).to include("HTTP aceito")
    expect(helper.tracking_attempt_badge(link, { "http_status" => 503 })).to include("Falhou")
    expect(helper.tracking_attempt_badge(link, { "error_class" => "Timeout::Error" })).to include("Sem confirmação")
    expect(helper.tracking_attempt_badge(link, { "status" => "received" })).to include("Recebido pela plataforma")
    expect(helper.tracking_attempt_badge(link, {})).to include("Estado desconhecido")
  end

  it "mantém o descarte GA4 sem sugerir que houve tentativa de rede" do
    link = instance_double(TrackingEventLink, transport: "ga4", delivery_status: "skipped")
    expect(helper.tracking_attempt_badge(link, { "at" => Time.current.iso8601 })).to include("Não enviado")
  end

  it "trata datas ausentes e inválidas sem quebrar a consulta" do
    expect(helper.tracking_audit_time(nil)).to eq("Não registrada")
    expect(helper.tracking_audit_time("invalid")).to eq("Data indisponível")
    expect(helper.tracking_reason_label("token=unsafe")).to eq("Motivo não catalogado")
  end
end
