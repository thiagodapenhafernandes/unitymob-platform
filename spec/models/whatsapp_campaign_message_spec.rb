require "rails_helper"

RSpec.describe WhatsappCampaignMessage, type: :model do
  let(:admin) { create(:admin_user, :admin) }
  let(:distribution_rule) { create(:distribution_rule, name: "Captação Alto Padrão") }
  let(:template) do
    WhatsappTemplate.create!(
      name: "campanha_botoes",
      language: "pt_BR",
      status: "APPROVED",
      body: "Escolha uma opção.",
      buttons: {
        "0" => { "kind" => "quick_reply", "text" => "Saiba mais" },
        "1" => { "kind" => "quick_reply", "text" => "Não tenho interesse" }
      }
    )
  end
  let(:conversation) { WhatsappConversation.create!(contact_phone: "5511999990000", status: "open") }

  it "normaliza telefone antes de validar" do
    simple_template = WhatsappTemplate.create!(
      name: "campanha_normaliza_telefone",
      language: "pt_BR",
      status: "APPROVED",
      body: "Mensagem de normalização"
    )
    campaign = WhatsappCampaign.create!(
      name: "Campanha telefone normalizado",
      whatsapp_template: simple_template,
      created_by: admin,
      status: "draft"
    )

    message = campaign.campaign_messages.build(phone_number: "47 9972-9441", status: "pending")

    expect(message).to be_valid
    expect(message.phone_number).to eq("5547999729441")
  end

  it "sinaliza mensagem enviada sem retorno de entrega apos a janela operacional" do
    simple_template = WhatsappTemplate.create!(
      name: "campanha_status_entrega",
      language: "pt_BR",
      status: "APPROVED",
      body: "Mensagem de status"
    )
    campaign = WhatsappCampaign.create!(
      name: "Campanha aguardando status",
      whatsapp_template: simple_template,
      created_by: admin,
      status: "completed"
    )
    message = campaign.campaign_messages.create!(
      phone_number: "5511999990000",
      status: "sent",
      sent_at: 6.minutes.ago
    )

    expect(message).to be_delivery_unconfirmed
    expect(message.status).to eq("sent")
    expect(message.display_status_label).to eq("Sem retorno de entrega")
    expect(message.status_note).to eq("Aguardando webhook de entrega/leitura da Meta.")
  end

  it "classifica avisos operacionais da Meta sem tratar como erro critico" do
    details = described_class.normalize_failure_reason(
      "Unable to deliver message | código 131049"
    )

    expect(details).to include(
      group_key: "code:131049",
      label: "Envio limitado pela Meta para manter engajamento saudável",
      technical: "código 131049",
      severity: "warning"
    )
  end

  it "classifica template pausado como erro critico antes de reprocessar" do
    details = described_class.normalize_failure_reason(
      "Template paused due to low quality (132015)"
    )

    expect(details).to include(
      group_key: "code:132015",
      label: "Template pausado pela Meta por baixa qualidade",
      technical: "código 132015",
      severity: "error"
    )
  end

  it "agenda retry mais conservador para limite de engajamento da Meta" do
    simple_template = WhatsappTemplate.create!(
      name: "campanha_retry_meta",
      language: "pt_BR",
      status: "APPROVED",
      body: "Mensagem de retry"
    )
    campaign = WhatsappCampaign.create!(
      name: "Campanha retry Meta",
      whatsapp_template: simple_template,
      created_by: admin,
      status: "processing"
    )
    message = campaign.campaign_messages.create!(
      phone_number: "5511999990001",
      status: "sent",
      sent_at: 1.minute.ago
    )

    before_failure = Time.current
    message.mark_failed!("Envio limitado pela Meta para manter engajamento saudável (código 131049)")
    after_failure = Time.current

    expect(message.reload.retry_count).to eq(1)
    expect(message.next_retry_at).to be_between(before_failure + 6.hours, after_failure + 6.hours)
  end

  it "estrutura clique de botao, converte destinatario em lead e alimenta cards dinamicos" do
    campaign = WhatsappCampaign.create!(
      name: "Campanha com decisão",
      whatsapp_template: template,
      created_by: admin,
      status: "processing",
      response_decisions: {
        buttons: [
          {
            key: template.interactive_buttons.first["key"],
            text: "Saiba mais",
            kind: "quick_reply",
            action: "generate_lead",
            distribution_rule_id: distribution_rule.id
          }
        ]
      }
    )
    recipient = campaign.campaign_recipients.create!(
      name: "Maria Campanha",
      phone_number: "11999990000",
      email: "maria@example.com",
      source: "spreadsheet"
    )
    message = campaign.campaign_messages.create!(
      whatsapp_campaign_recipient: recipient,
      phone_number: "5511999990000",
      status: "sent",
      sent_at: 1.minute.ago
    )
    inbound = WhatsappMessage.create!(
      whatsapp_conversation: conversation,
      direction: "inbound",
      msg_type: "button",
      body: "Saiba mais",
      status: "delivered",
      wa_message_id: "wamid.reply"
    )

    expect {
      message.mark_replied!(
        inbound_message: inbound,
        raw_payload: {
          "id" => "wamid.reply",
          "type" => "button",
          "button" => { "text" => "Saiba mais", "payload" => "payload-saiba-mais" }
        }
      )
    }.to change(Lead, :count).by(1)

    expect(message.reload.reply_type).to eq("button")
    expect(message.reply_button_text).to eq("Saiba mais")
    expect(message.reply_button_payload).to eq("payload-saiba-mais")
    expect(message.lead).to eq(recipient.reload.lead)
    expect(recipient.conversion_status).to eq("converted")
    expect(recipient.lead.distribution_rule_id).to eq(distribution_rule.id)
    expect(campaign.reload.dynamic_response_cards.find { |card| card[:label] == "Saiba mais" }[:count]).to eq(1)
  end

  it "marca destinatario sem interesse sem criar lead" do
    campaign = WhatsappCampaign.create!(
      name: "Campanha sem interesse",
      whatsapp_template: template,
      created_by: admin,
      status: "processing",
      response_decisions: {
        buttons: [
          {
            key: template.interactive_buttons.first["key"],
            text: "Saiba mais",
            kind: "quick_reply",
            action: "ignore"
          },
          {
            key: template.interactive_buttons.second["key"],
            text: "Não tenho interesse",
            kind: "quick_reply",
            action: "mark_no_interest"
          }
        ]
      }
    )
    recipient = campaign.campaign_recipients.create!(
      name: "Contato Frio",
      phone_number: "11988880000",
      source: "spreadsheet"
    )
    message = campaign.campaign_messages.create!(
      whatsapp_campaign_recipient: recipient,
      phone_number: "5511988880000",
      status: "sent"
    )
    inbound = WhatsappMessage.create!(
      whatsapp_conversation: conversation,
      direction: "inbound",
      msg_type: "button",
      body: "Não tenho interesse",
      status: "delivered",
      wa_message_id: "wamid.no-interest"
    )

    expect {
      message.mark_replied!(
        inbound_message: inbound,
        raw_payload: { "type" => "button", "button" => { "text" => "Não tenho interesse" } }
      )
    }.not_to change(Lead, :count)

    expect(recipient.reload.conversion_status).to eq("no_interest")
    expect(message.reload.lead_id).to be_nil
  end

  it "descadastra destinatario no numero de envio para futuras campanhas" do
    sender = create(:whatsapp_sender_number)
    unsubscribe_template = WhatsappTemplate.create!(
      name: "campanha_descadastro",
      language: "pt_BR",
      status: "APPROVED",
      body: "Escolha uma opção.",
      buttons: {
        "0" => { "kind" => "quick_reply", "text" => "Descadastrar" }
      }
    )
    campaign = WhatsappCampaign.create!(
      name: "Campanha opt-out",
      whatsapp_template: unsubscribe_template,
      whatsapp_sender_number: sender,
      created_by: admin,
      status: "processing",
      response_decisions: {
        buttons: [
          {
            key: unsubscribe_template.interactive_buttons.first["key"],
            text: "Descadastrar",
            kind: "quick_reply",
            action: "unsubscribe"
          }
        ]
      }
    )
    recipient = campaign.campaign_recipients.create!(
      name: "Contato Opt-out",
      phone_number: "11977770000",
      source: "spreadsheet"
    )
    message = campaign.campaign_messages.create!(
      whatsapp_campaign_recipient: recipient,
      phone_number: "5511977770000",
      status: "sent"
    )
    inbound = WhatsappMessage.create!(
      whatsapp_conversation: conversation,
      direction: "inbound",
      msg_type: "button",
      body: "Descadastrar",
      status: "delivered",
      wa_message_id: "wamid.unsubscribe"
    )

    expect {
      message.mark_replied!(
        inbound_message: inbound,
        raw_payload: { "id" => "wamid.unsubscribe", "type" => "button", "button" => { "text" => "Descadastrar", "payload" => "Descadastrar" } }
      )
    }.to change(WhatsappCampaignUnsubscribe.active, :count).by(1)

    unsubscribe = WhatsappCampaignUnsubscribe.active.last
    expect(recipient.reload.conversion_status).to eq("unsubscribed")
    expect(unsubscribe.whatsapp_sender_number).to eq(sender)
    expect(unsubscribe.phone_number).to eq("5511977770000")
    expect(unsubscribe.whatsapp_campaign_message).to eq(message)
    expect(unsubscribe.unsubscribed_by_message).to eq(inbound)
  end
end
