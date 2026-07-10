# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "phones:normalize" do
  before(:all) do
    Rails.application.load_tasks
  end

  after do
    ENV.delete("EXECUTE")
    Rake::Task["phones:normalize"].reenable
    Rake::Task["phones:reconcile_whatsapp_conversation_conflicts"].reenable
  end

  it "mantem dry-run sem alterar dados existentes" do
    lead = create(:lead)
    lead.update_column(:phone, "47 9972-9441")

    expect { run_task }.not_to change { lead.reload.phone }
  end

  it "normaliza telefones corrigiveis quando EXECUTE=1" do
    ENV["EXECUTE"] = "1"
    lead = create(:lead)
    conversation = WhatsappConversation.create!(tenant: Current.tenant, contact_phone: "5547999990000")
    lead.update_column(:phone, "47 9972-9441")
    conversation.update_column(:contact_phone, "47 8888-0000")

    run_task

    expect(lead.reload.phone).to eq("5547999729441")
    expect(conversation.reload.contact_phone).to eq("5547988880000")
  end

  it "nao apaga automaticamente telefones invalidos" do
    ENV["EXECUTE"] = "1"
    lead = create(:lead)
    lead.update_column(:phone, "0000")

    run_task

    expect(lead.reload.phone).to eq("0000")
  end

  it "nao aborta quando um telefone normalizado conflita com indice unico existente" do
    ENV["EXECUTE"] = "1"
    tenant = Current.tenant
    existing = WhatsappConversation.create!(tenant:, contact_phone: "5548988516745")
    conflicting = WhatsappConversation.create!(tenant:, business_scoped_user_id: "bsuid-conflict")
    conflicting.update_column(:contact_phone, "554888516745")

    expect { run_task }.not_to raise_error

    expect(existing.reload.contact_phone).to eq("5548988516745")
    expect(conflicting.reload.contact_phone).to eq("554888516745")
  end

  it "reconcilia conversas WhatsApp duplicadas por telefone normalizado preservando mensagens e contexto" do
    ENV["EXECUTE"] = "1"
    tenant = Current.tenant
    lead = create(:lead, tenant:)
    legacy = WhatsappConversation.create!(
      tenant:,
      lead:,
      business_scoped_user_id: "BR.1348960100001490",
      contact_name: "Cliente antigo",
      unread_count: 1
    )
    legacy.update_column(:contact_phone, "554888516745")
    normalized = WhatsappConversation.create!(
      tenant:,
      contact_phone: "5548988516745",
      contact_name: "Cliente normalizado",
      unread_count: 2
    )
    WhatsappMessage.create!(tenant:, whatsapp_conversation: legacy, direction: "inbound", body: "Mensagem antiga", created_at: 2.hours.ago, updated_at: 2.hours.ago)
    WhatsappMessage.create!(tenant:, whatsapp_conversation: normalized, direction: "inbound", body: "Mensagem nova", created_at: 1.hour.ago, updated_at: 1.hour.ago)

    expect { run_reconcile_task }.to change(WhatsappConversation, :count).by(-1)

    canonical = WhatsappConversation.find_by!(tenant:, contact_phone: "5548988516745")
    expect(canonical.id).to eq(legacy.id)
    expect(canonical.lead_id).to eq(lead.id)
    expect(canonical.business_scoped_user_id).to eq("BR.1348960100001490")
    expect(canonical.unread_count).to eq(3)
    expect(canonical.messages.pluck(:body)).to contain_exactly("Mensagem antiga", "Mensagem nova")
    expect(WhatsappConversation.exists?(normalized.id)).to be(false)
  end

  it "mantem o backfill alinhado aos campos normalizados pelos models" do
    Rails.application.eager_load!

    task_fields = Object.const_get(:PHONE_FIELDS)
    ApplicationRecord.descendants.each do |model|
      next unless model.respond_to?(:phone_fields_to_normalize)
      next if model.phone_fields_to_normalize.blank?
      next unless model.respond_to?(:table_name)

      expected_fields = model.phone_fields_to_normalize.keys.map(&:to_s)
      expect(task_fields.fetch(model.table_name, [])).to include(*expected_fields)
    end

    expect(task_fields).to include(
      "whatsapp_campaign_messages" => include("phone_number"),
      "whatsapp_campaign_recipients" => include("phone_number"),
      "whatsapp_campaign_unsubscribes" => include("phone_number")
    )
  end

  it "cobre todos os campos persistidos que representam telefone real" do
    task_fields = Object.const_get(:PHONE_FIELDS)
    phone_like_pattern = /(phone|telefone|celular|whatsapp|mobile|residential|business|fone)/i
    technical_or_non_phone_fields = {
      "client_interactions" => %w[business_id],
      "client_property_interests" => %w[business_id],
      "contact_settings" => %w[business_hours],
      "crm_appointments" => %w[business_id],
      "crm_contacts" => %w[show_phone_on_web],
      "distribution_rules" => %w[business_type notify_whatsapp],
      "habitation_interactions" => %w[business_id],
      "lead_settings" => %w[secure_link_whatsapp],
      "leads" => %w[business_scoped_user_id],
      "notification_template_settings" => %w[whatsapp_template_id],
      "portal_integrations" => %w[allowed_business_types],
      "proprietors" => %w[phone_extension show_phone_on_web],
      "system_notification_settings" => %w[
        whatsapp_access_token
        whatsapp_app_secret
        whatsapp_business_account_id
        whatsapp_enabled
        whatsapp_phone_number_id
        whatsapp_template_name
      ],
      "tenants" => %w[use_global_whatsapp_fallback],
      "webhook_settings" => %w[whatsapp_webhook_url],
      "whatsapp_business_integrations" => %w[business_id phone_number_id],
      "whatsapp_campaign_messages" => %w[
        whatsapp_campaign_id
        whatsapp_campaign_recipient_id
        whatsapp_message_id
      ],
      "whatsapp_campaign_recipients" => %w[whatsapp_campaign_id],
      "whatsapp_campaign_unsubscribes" => %w[
        whatsapp_campaign_id
        whatsapp_campaign_message_id
        whatsapp_campaign_recipient_id
        whatsapp_sender_number_id
      ],
      "whatsapp_campaigns" => %w[whatsapp_sender_number_id whatsapp_template_id],
      "whatsapp_conversations" => %w[business_scoped_user_id],
      "whatsapp_messages" => %w[whatsapp_conversation_id],
      "whatsapp_sender_numbers" => %w[phone_number_id whatsapp_business_integration_id]
    }

    missing_fields = ActiveRecord::Base.connection.tables.sort.flat_map do |table|
      ActiveRecord::Base.connection.columns(table).filter_map do |column|
        next unless column.name.match?(phone_like_pattern)
        next if task_fields.fetch(table, []).include?(column.name)
        next if technical_or_non_phone_fields.fetch(table, []).include?(column.name)

        "#{table}.#{column.name}"
      end
    end

    expect(missing_fields).to be_empty
  end

  def run_task
    Rake::Task["phones:normalize"].invoke
  ensure
    Rake::Task["phones:normalize"].reenable
  end

  def run_reconcile_task
    Rake::Task["phones:reconcile_whatsapp_conversation_conflicts"].invoke
  ensure
    Rake::Task["phones:reconcile_whatsapp_conversation_conflicts"].reenable
  end
end
