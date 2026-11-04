require "rails_helper"

RSpec.describe WhatsappConversation do
  let(:tenant) { Tenant.default }
  let(:integration) { WhatsappBusinessIntegration.current(tenant).tap { |i| i.update!(separate_conversations_by_number: true) } }
  let(:main) { create(:whatsapp_sender_number, tenant: tenant, whatsapp_business_integration: integration) }
  let(:notifications) { create(:whatsapp_sender_number, tenant: tenant, whatsapp_business_integration: integration, administrative_inbox_enabled: false) }

  it "isola o mesmo contato e BSUID por número, mantendo unicidade em cada histórico" do
    first = described_class.contact_scope(tenant: tenant, sender_number: main).create!(contact_phone: "5547999991111", business_scoped_user_id: "US.same")
    second = described_class.contact_scope(tenant: tenant, sender_number: notifications).create!(contact_phone: first.contact_phone, business_scoped_user_id: first.business_scoped_user_id)
    expect(first.id).not_to eq(second.id)
    expect(second.administrative_inbox?).to be(false)
    expect(described_class.administrative_inbox).to include(first)
    expect(described_class.administrative_inbox).not_to include(second)
    duplicate = described_class.new(tenant: tenant, whatsapp_sender_number: main, contact_phone: first.contact_phone)
    expect(duplicate).not_to be_valid
    expect(integration.update(separate_conversations_by_number: false)).to be(false)
  end

  it "preserva o histórico único quando a conta não opta pela separação" do
    main
    integration.update!(separate_conversations_by_number: false)
    conversation = described_class.create!(tenant: tenant, contact_phone: "5547999992222", whatsapp_sender_number: main)
    expect(described_class.contact_scope(tenant: tenant, sender_number: notifications).find_by(contact_phone: conversation.contact_phone)).to eq(conversation)
  end

  it "não usa outro remetente nem gera alerta administrativo para número dedicado" do
    conversation = described_class.contact_scope(tenant: tenant, sender_number: notifications).create!(
      contact_phone: "5547999997777", assigned_admin_user: create(:admin_user, tenant: tenant))
    expect(notifications.messaging_ready?).to be(false)
    expect(conversation.reply_credentials).to eq(notifications)
    expect(conversation.alert_recipient_id).to be_nil
  end

  it "rejeita número de outra conta no escopo e no registro" do
    main
    foreign = create(:whatsapp_sender_number, tenant: Tenant.create!(name: "Outra conta", slug: "outra-#{SecureRandom.hex(4)}"), whatsapp_business_integration: nil)
    expect { described_class.contact_scope(tenant: tenant, sender_number: foreign) }.to raise_error(ArgumentError)
    conversation = described_class.new(tenant: tenant, whatsapp_sender_number: foreign, contact_phone: "5547999993333")
    expect(conversation).not_to be_valid
  end
end
