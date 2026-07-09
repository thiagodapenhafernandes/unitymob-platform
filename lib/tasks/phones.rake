# frozen_string_literal: true

namespace :phones do
  PHONE_FIELDS = {
    "admin_users" => %w[phone],
    "captacoes" => %w[proprietario_telefone],
    "contact_settings" => %w[whatsapp_primary whatsapp_secondary phone],
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
    "whatsapp_campaign_recipients" => %w[phone_number],
    "whatsapp_campaign_unsubscribes" => %w[phone_number],
    "whatsapp_sender_numbers" => %w[display_phone_number]
  }.freeze

  desc "Normaliza telefones para E.164 sem +. DRY-RUN por padrão; use EXECUTE=1 para aplicar."
  task normalize: :environment do
    require "csv"

    execute = ENV["EXECUTE"] == "1"
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    log_path = Rails.root.join("log", "phone_normalization_#{timestamp}.csv")
    changed = 0
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
          action = new_value.present? ? "normalize" : "blank_invalid"
          next if new_value.to_s == old_value.to_s

          csv << [table, row["id"], field, old_value, new_value, action]
          updates[field] = new_value
          changed += 1
          invalid += 1 if new_value.blank?
        end

        next unless execute && updates.any?

        assignments = updates.map do |field, value|
          "#{ActiveRecord::Base.connection.quote_column_name(field)} = #{ActiveRecord::Base.connection.quote(value)}"
        end
        assignments << "updated_at = #{ActiveRecord::Base.connection.quote(Time.current)}" if ActiveRecord::Base.connection.column_exists?(table, "updated_at")

        ActiveRecord::Base.connection.update(
          "UPDATE #{quoted_table} SET #{assignments.join(', ')} WHERE id = #{row['id'].to_i}"
        )
      end
    end

    csv.close

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'} phones:normalize"
    puts "#{scanned} telefones lidos | #{changed} alterações #{execute ? 'aplicadas' : 'previstas'} | #{invalid} inválidos/lixo para limpar"
    puts "log: #{log_path}"
  end
end
