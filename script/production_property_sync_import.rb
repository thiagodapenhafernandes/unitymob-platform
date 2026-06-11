# frozen_string_literal: true

require "json"
require "set"

file_path = ENV.fetch("FILE")
dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
create_missing = ActiveModel::Type::Boolean.new.cast(ENV.fetch("CREATE_MISSING", "false"))
sync_proprietors = ActiveModel::Type::Boolean.new.cast(ENV.fetch("SYNC_PROPRIETORS", "true"))
sync_brokers = ActiveModel::Type::Boolean.new.cast(ENV.fetch("SYNC_BROKERS", "true"))
limit = ENV["LIMIT"].to_i.positive? ? ENV["LIMIT"].to_i : nil
progress_every = [ENV.fetch("PROGRESS_EVERY", "250").to_i, 1].max
only_codes = ENV.fetch("ONLY_CODES", "").split(",").map(&:strip).reject(&:blank?).to_set

habitation_excluded_columns = %w[
  id codigo slug created_at updated_at admin_user_id proprietor_id constructor_id admin_reviewed_by_id
]
habitation_columns = Habitation.column_names - habitation_excluded_columns
habitation_integer_columns = Habitation.columns_hash.select { |_name, column| column.type == :integer && column.limit.to_i <= 4 }
proprietor_columns = defined?(Proprietor) ? (Proprietor.column_names - %w[id created_at updated_at]) : []
assignment_columns = defined?(HabitationBrokerAssignment) ? (HabitationBrokerAssignment.column_names - %w[id habitation_id admin_user_id created_at updated_at]) : []

stats = Hash.new(0)
errors = []
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def admin_user_for(vista_id, email)
  normalized_vista_id = vista_id.to_s.strip
  return AdminUser.find_by(vista_id: normalized_vista_id) if normalized_vista_id.present?

  normalized_email = email.to_s.strip.downcase
  return nil if normalized_email.blank?

  AdminUser.find_by("lower(email) = ?", normalized_email)
end

File.foreach(file_path).with_index(1) do |line, line_number|
  break if limit && stats[:scanned] >= limit

  row = JSON.parse(line)
  vista_codigo = row.fetch("vista_codigo").to_s.strip
  next if only_codes.any? && !only_codes.include?(vista_codigo)

  stats[:scanned] += 1

  habitation = Habitation.find_by(codigo: vista_codigo)
  if habitation.nil?
    if create_missing
      habitation = Habitation.new(codigo: vista_codigo)
      stats[:would_create] += 1
    else
      stats[:missing] += 1
      next
    end
  end

  attrs = row.fetch("habitation_attributes", {}).slice(*habitation_columns)

  habitation_integer_columns.each do |column_name, _column|
    next unless attrs.key?(column_name)
    next if attrs[column_name].nil?

    integer_value = attrs[column_name].to_i
    next if integer_value.between?(-2_147_483_648, 2_147_483_647)

    attrs.delete(column_name)
    stats[:integer_overflow_fields_skipped] += 1
  end

  codigo_dwv = attrs["codigo_dwv"].to_s.strip
  if codigo_dwv.present? && Habitation.where(codigo_dwv: codigo_dwv).where.not(id: habitation.id).exists?
    attrs.delete("codigo_dwv")
    stats[:duplicate_codigo_dwv_skipped] += 1
  end

  admin_user = admin_user_for(row["admin_user_vista_id"], row["admin_user_email"])
  attrs["admin_user_id"] = admin_user.id if admin_user

  proprietor_payload = row["proprietor"]
  proprietor = nil
  if sync_proprietors && proprietor_payload.present? && defined?(Proprietor)
    proprietor_attrs = proprietor_payload.fetch("attributes", {}).slice(*proprietor_columns)
    vista_code = proprietor_payload["vista_code"].to_s.strip.presence || proprietor_attrs["vista_code"].to_s.strip.presence
    proprietor_name = proprietor_attrs["name"].to_s.strip.presence

    if vista_code.present? || proprietor_name.present?
      proprietor = (vista_code.present? && Proprietor.find_by(vista_code: vista_code)) ||
                   (proprietor_name.present? && Proprietor.find_by(name: proprietor_name)) ||
                   Proprietor.new
      proprietor.assign_attributes(proprietor_attrs)
      proprietor.vista_code = vista_code if vista_code.present?
      proprietor.name = proprietor_name.presence || "Proprietário sem nome" if proprietor.name.blank?
      attrs["proprietor_id"] = proprietor.id if proprietor.persisted?
      stats[proprietor.persisted? ? :proprietors_matched : :proprietors_would_create] += 1
    end
  end

  habitation.assign_attributes(attrs)
  changed_columns = habitation.changed
  broker_rows = Array(row["broker_assignments"])
  mapped_brokers = if sync_brokers && defined?(HabitationBrokerAssignment)
                     broker_rows.filter_map do |assignment_row|
                       broker = admin_user_for(assignment_row["admin_user_vista_id"], assignment_row["admin_user_email"])
                       unless broker
                         stats[:broker_admin_missing] += 1
                         next
                       end

                       {
                         admin_user: broker,
                         attributes: assignment_row.fetch("attributes", {}).slice(*assignment_columns)
                       }
                     end
                   else
                     []
                   end

  stats[:would_update] += 1 if changed_columns.any? && !habitation.new_record?
  stats[:unchanged] += 1 if changed_columns.empty? && !habitation.new_record?
  stats[:broker_assignments_would_replace] += mapped_brokers.size if sync_brokers

  unless dry_run
    ActiveRecord::Base.transaction do
      if proprietor
        proprietor.save!(validate: false)
        habitation.proprietor_id = proprietor.id
      end

      habitation.save!(validate: false)

      if sync_brokers && defined?(HabitationBrokerAssignment)
        habitation.broker_assignments.destroy_all
        mapped_brokers.each do |broker_row|
          habitation.broker_assignments.create!(
            broker_row.fetch(:attributes).merge(admin_user: broker_row.fetch(:admin_user))
          )
        end
      end
    end
    stats[:updated] += 1
  end

  if (stats[:scanned] % progress_every).zero?
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    puts({
      scanned: stats[:scanned],
      missing: stats[:missing],
      would_update: stats[:would_update],
      unchanged: stats[:unchanged],
      errors: errors.size,
      elapsed_seconds: elapsed.round
    }.to_json)
  end
rescue StandardError => e
  stats[:errors] += 1
  errors << { line: line_number, vista_codigo: vista_codigo, error: "#{e.class}: #{e.message}" }
end

puts({
  dry_run: dry_run,
  create_missing: create_missing,
  sync_proprietors: sync_proprietors,
  sync_brokers: sync_brokers,
  stats: stats,
  errors: errors.first(20)
}.to_json)
