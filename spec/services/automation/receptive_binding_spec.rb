require "rails_helper"

RSpec.describe Automation::ReceptiveBinding do
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:workflow) { tenant.automation_workflows.create!(name: "Menu receptivo", created_by: admin) }
  let(:sender) { tenant.whatsapp_sender_numbers.create!(label: "Comercial", display_phone_number: "+5511999990000", phone_number_id: "pn-1", waba_id: "waba-1") }
  let(:template) do
    tenant.whatsapp_templates.create!(
      name: "menu", language: "pt_BR", status: "APPROVED", usage_context: "response_flow", waba_id: "waba-1", category: "UTILITY", body: "Olá!",
      buttons: [{ "kind" => "quick_reply", "text" => "Comprar" }, { "kind" => "quick_reply", "text" => "Alugar" }]
    )
  end
  let(:config) { { trigger: "whatsapp_flow_button", whatsapp_sender_number_id: sender.id.to_s, whatsapp_template_id: template.id.to_s, use_as_receptive: true } }

  it "cria o fluxo de resposta com todos os botões em Iniciar automação e aponta o número para ele" do
    described_class.call(workflow, config)

    flow = tenant.whatsapp_response_flows.find_by!(whatsapp_template_id: template.id)
    expect(flow).to have_attributes(active: true, automation_workflow_id: workflow.id)
    expect(flow.button_actions.values.map { |row| row["action"] }.uniq).to eq(["run_automation"])
    expect(flow.button_actions.values.map { |row| row["automation_workflow_id"] }.uniq).to eq([workflow.id.to_s])
    expect(sender.reload.receptive_response_flow_id).to eq(flow.id)
  end

  it "é idempotente ao publicar de novo" do
    2.times { described_class.call(workflow, config) }

    expect(tenant.whatsapp_response_flows.where(whatsapp_template_id: template.id).count).to eq(1)
  end

  it "não sobrescreve um fluxo de resposta que já existe para o template" do
    other = tenant.automation_workflows.create!(name: "Outra")
    tenant.whatsapp_response_flows.create!(name: "Menu do time", whatsapp_template: template, automation_workflow: other)

    expect { described_class.call(workflow, config) }.to raise_error(described_class::Error, /Menu do time/)
    expect(sender.reload.receptive_response_flow_id).to be_nil
  end

  it "desligar o receptivo solta o número e desativa o fluxo criado por aqui" do
    described_class.call(workflow, config)
    described_class.call(workflow, config.merge(use_as_receptive: false))

    expect(sender.reload.receptive_response_flow_id).to be_nil
    expect(tenant.whatsapp_response_flows.find_by(whatsapp_template_id: template.id)).to have_attributes(active: false)
  end

  it "trocar o gatilho também solta o receptivo" do
    described_class.call(workflow, config)
    described_class.call(workflow, config.merge(trigger: "lead_created"))

    expect(sender.reload.receptive_response_flow_id).to be_nil
  end

  it "exige número e template quando o receptivo está ligado" do
    expect { described_class.call(workflow, config.merge(whatsapp_sender_number_id: "")) }.to raise_error(described_class::Error, /número/)
    expect { described_class.call(workflow, config.merge(whatsapp_template_id: "")) }.to raise_error(described_class::Error, /template/)
  end
end
