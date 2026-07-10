# frozen_string_literal: true

namespace :phones do
  PHONE_FIELDS = {
    "admin_users" => %w[phone secondary_phone],
    "captacoes" => %w[proprietario_telefone],
    "contact_settings" => %w[whatsapp_primary whatsapp_secondary phone],
    "crm_contacts" => %w[phone_primary mobile_phone residential_phone business_phone],
    "footer_settings" => %w[whatsapp],
    "footer_stores" => %w[phone],
    "habitations" => %w[
      corretor_telefone
      proprietario_celular
      proprietario_telefone_comercial
      proprietario_telefone_residencial
      zelador_telefone
    ],
    "leads" => %w[phone client_phone agent_phone],
    "proprietors" => %w[
      phone_primary
      mobile_phone
      residential_phone
      business_phone
      spouse_phone
    ],
    "stores" => %w[phone],
    "whatsapp_business_integrations" => %w[
      default_whatsapp_number
      sale_whatsapp_number
      rent_whatsapp_number
      sale_rent_whatsapp_number
    ],
    "whatsapp_campaign_messages" => %w[phone_number],
    "whatsapp_campaign_recipients" => %w[phone_number],
    "whatsapp_campaign_unsubscribes" => %w[phone_number],
    "whatsapp_conversations" => %w[contact_phone],
    "whatsapp_sender_numbers" => %w[display_phone_number]
  }.freeze

  desc "Normaliza telefones para E.164 sem +. DRY-RUN por padrão; use EXECUTE=1 para aplicar."
  task normalize: :environment do
    require "csv"

    execute = ENV["EXECUTE"] == "1"
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    log_path = Rails.root.join("log", "phone_normalization_#{timestamp}.csv")
    changed = 0
    conflicts = 0
    invalid = 0
    scanned = 0

    csv = CSV.open(log_path, "w")
    csv << %w[table id field old_value new_value action]

    PHONE_FIELDS.each do |table, fields|
      next unless ActiveRecord::Base.connection.data_source_exists?(table)

      existing_fields = fields.select { |field| ActiveRecord::Base.connection.column_exists?(table, field) }
      next if existing_fields.blank?

      select_columns = ["id", *existing_fields].join(", ")
      quoted_table = ActiveRecord::Base.connection.quote_table_name(table)

      ActiveRecord::Base.connection.select_all("SELECT #{select_columns} FROM #{quoted_table}").each do |row|
        updates = {}

        existing_fields.each do |field|
          old_value = row[field]
          next if old_value.blank?

          scanned += 1
          new_value = Phones::Normalizer.call(old_value)
          next if new_value.to_s == old_value.to_s

          if new_value.blank?
            csv << [table, row["id"], field, old_value, new_value, "blank_invalid"]
            invalid += 1
            next
          end

          csv << [table, row["id"], field, old_value, new_value, "normalize"] unless execute
          updates[field] = new_value
          changed += 1
        end

        next unless execute && updates.any?

        assignments = updates.map do |field, value|
          "#{ActiveRecord::Base.connection.quote_column_name(field)} = #{ActiveRecord::Base.connection.quote(value)}"
        end
        assignments << "updated_at = #{ActiveRecord::Base.connection.quote(Time.current)}" if ActiveRecord::Base.connection.column_exists?(table, "updated_at")

        begin
          ActiveRecord::Base.transaction(requires_new: true) do
            ActiveRecord::Base.connection.update(
              "UPDATE #{quoted_table} SET #{assignments.join(', ')} WHERE id = #{row['id'].to_i}"
            )
          end
          updates.each do |field, value|
            csv << [table, row["id"], field, row[field], value, "normalized"]
          end
        rescue ActiveRecord::RecordNotUnique => error
          conflicts += 1
          changed -= updates.size
          updates.each do |field, value|
            csv << [table, row["id"], field, row[field], value, "conflict_unique: #{error.cause&.message || error.message}".truncate(180)]
          end
        end
      end
    end

    csv.close

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'} phones:normalize"
    puts "#{scanned} telefones lidos | #{changed} alterações #{execute ? 'aplicadas' : 'previstas'} | #{invalid} inválidos/lixo para limpar | #{conflicts} conflitos únicos"
    puts "log: #{log_path}"
  end

  desc "Reconcilia conversas WhatsApp que colidem após normalização de telefone. DRY-RUN por padrão; use EXECUTE=1 para aplicar."
  task reconcile_whatsapp_conversation_conflicts: :environment do
    require "csv"
    require "set"

    execute = ENV["EXECUTE"] == "1"
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    log_path = Rails.root.join("log", "phone_conversation_conflicts_#{timestamp}.csv")
    scanned = 0
    candidates = 0
    merged = 0
    skipped = 0
    processed_ids = Set.new

    csv = CSV.open(log_path, "w")
    csv << %w[source_id duplicate_id canonical_id duplicate_removed_id tenant_id old_phone normalized_phone action details]

    WhatsappConversation.where.not(contact_phone: [nil, ""]).find_each do |conversation|
      next if processed_ids.include?(conversation.id)

      scanned += 1
      normalized_phone = Phones::Normalizer.call(conversation.contact_phone)
      next if normalized_phone.blank? || normalized_phone == conversation.contact_phone

      duplicate = WhatsappConversation
        .where(tenant_id: conversation.tenant_id, contact_phone: normalized_phone)
        .where.not(id: conversation.id)
        .first
      next unless duplicate

      candidates += 1
      pair = [conversation, duplicate]
      canonical = pair.max_by do |item|
        [
          item.business_scoped_user_id.present? ? 1 : 0,
          item.lead_id.present? ? 1 : 0,
          item.messages.count,
          item.last_message_at || item.updated_at || Time.zone.at(0),
          -item.id
        ]
      end
      duplicate_to_remove = (pair - [canonical]).first

      csv << [
        conversation.id,
        duplicate.id,
        canonical.id,
        duplicate_to_remove.id,
        conversation.tenant_id,
        conversation.contact_phone,
        normalized_phone,
        execute ? "merge" : "merge_candidate",
        "messages=#{pair.sum { |item| item.messages.count }}"
      ]

      next unless execute

      begin
        WhatsappConversation.transaction(requires_new: true) do
          message_scope = WhatsappMessage.where(whatsapp_conversation_id: duplicate_to_remove.id)
          message_scope.update_all(whatsapp_conversation_id: canonical.id, updated_at: Time.current)

          latest_message = WhatsappMessage.where(whatsapp_conversation_id: canonical.id).order(created_at: :desc).first
          canonical_updates = {
            contact_phone: normalized_phone,
            business_scoped_user_id: canonical.business_scoped_user_id.presence || duplicate_to_remove.business_scoped_user_id,
            lead_id: canonical.lead_id || duplicate_to_remove.lead_id,
            assigned_admin_user_id: canonical.assigned_admin_user_id || duplicate_to_remove.assigned_admin_user_id,
            contact_name: canonical.contact_name.presence || duplicate_to_remove.contact_name,
            unread_count: canonical.unread_count.to_i + duplicate_to_remove.unread_count.to_i,
            last_message_at: latest_message&.created_at || [canonical.last_message_at, duplicate_to_remove.last_message_at].compact.max,
            last_message_preview: latest_message&.preview || canonical.last_message_preview.presence || duplicate_to_remove.last_message_preview,
            updated_at: Time.current
          }.compact

          duplicate_to_remove.destroy!
          canonical.update_columns(canonical_updates)
        end

        processed_ids << conversation.id << duplicate.id
        merged += 1
      rescue StandardError => error
        skipped += 1
        csv << [
          conversation.id,
          duplicate.id,
          canonical.id,
          duplicate_to_remove.id,
          conversation.tenant_id,
          conversation.contact_phone,
          normalized_phone,
          "merge_failed",
          "#{error.class}: #{error.message}".truncate(180)
        ]
      end
    end

    csv.close

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'} phones:reconcile_whatsapp_conversation_conflicts"
    puts "#{scanned} conversas lidas | #{candidates} conflitos candidatos | #{merged} merges aplicados | #{skipped} falhas"
    puts "log: #{log_path}"
  end
end
