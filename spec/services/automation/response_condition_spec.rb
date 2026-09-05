require "rails_helper"

RSpec.describe Automation::ResponseCondition do
  def matches(payload: {}, body: "Olá", lead: nil, **condition)
    described_class.new(payload: payload, lead: lead) { body }.matches?(condition)
  end

  it "preserva operadores, comparação sem caixa e tratamento de esperado vazio" do
    expect(matches(field: "message.body", value: " olá ")).to be true
    expect(matches(field: "message.body", operator: "contains", value: "LÁ")).to be true
    expect(matches(field: "message.body", operator: "not_contains", value: "LÁ")).to be false
    %w[contains not_contains].each do |operator|
      expect(matches(body: nil, field: "message.body", operator: operator, value: " ")).to be true
    end
    expect(matches(body: nil, field: "message.body", operator: "present")).to be false
    expect(matches(field: "message.body", operator: "present")).to be true
  end

  it "não busca o corpo quando o campo ou botão já resolve a condição" do
    condition = described_class.new(payload: { button: { title: "Sim" } }, lead: nil) { raise "Consulta desnecessária" }
    expect(condition.matches?(field: "interaction.button_text", value: "Sim")).to be true
    expect(condition.matches?(field: "lead.status", operator: "present")).to be false
  end

  it "mantém precedência de botão, interactive, campos legados e corpo" do
    payload = { button: { id: "first", title: "Primeiro" }, interactive: { button_reply: { id: "second", title: "Segundo" } }, button_payload: "third", button_text: "Terceiro", button_id: "fourth" }
    [["first", "Primeiro"], ["second", "Segundo"], ["third", "Terceiro"], ["fourth", "Olá"]].each_with_index do |(id, title), index|
      expect(matches(payload: payload, field: "interaction.button_payload", value: id)).to be true
      expect(matches(payload: payload, field: "interaction.button_text", value: title)).to be true
      case index
      when 0 then payload.delete(:button)
      when 1 then payload.delete(:interactive)
      when 2 then payload.except!(:button_payload, :button_text)
      end
    end
  end

  it "aceita fallback por texto e aliases legados sem aceitar resposta diferente" do
    expect(matches(match_strategy: "button_payload_or_text", button_key: "ok", payload: { button_id: "OK" })).to be true
    expect(matches(match_strategy: "button_payload_or_text", button_payload: "no", fallback_value: "OLÁ")).to be true
    expect(matches(match_strategy: "button_payload_or_text", value: "no", button_text: "tchau")).to be false
  end

  it "resolve campanha, lead, guardrails e caminhos aninhados com chaves string" do
    payload = { "response_decision" => { "action" => "accept", "action_label" => "Aceitar", "distribution_rule_id" => 42 }, "outside_hours" => true, "crm_error" => false, "custom" => { "name" => "valor" } }
    { "campaign.response_decision.action" => "accept", "campaign.response_decision.label" => "Aceitar", "campaign.response_decision.distribution_rule_id" => "42", "guardrail.outside_hours" => "true", "guardrail.crm_error" => "false", "custom.name" => "valor", "lead.status" => "Em Atendimento", "lead.lifecycle" => "Em Atendimento" }.each do |field, value|
      expect(matches(payload: payload, lead: double(status: "Em Atendimento"), field: field, value: value)).to be true
    end
    expect(matches(field: "lead.status", operator: "present")).to be false
  end
end
