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
end
