# frozen_string_literal: true

require "json"
require "fileutils"

output_path = ENV["OUTPUT"].presence ||
              Rails.root.join("tmp", "production_property_sync", "habitations_#{Time.current.strftime('%Y%m%d%H%M%S')}.jsonl").to_s
limit = ENV["LIMIT"].to_i.positive? ? ENV["LIMIT"].to_i : nil

FileUtils.mkdir_p(File.dirname(output_path))

excluded_habitation_columns = %w[
  id codigo slug created_at updated_at admin_user_id proprietor_id constructor_id admin_reviewed_by_id
  vista_import_batch_id vista_payload vista_codigo vista_imo_codigo vista_imo_placa vista_referencia_externa
]

excluded_proprietor_columns = %w[
  id created_at updated_at vista_import_batch_id vista_payload
]

excluded_assignment_columns = %w[
  id habitation_id admin_user_id created_at updated_at vista_import_batch_id vista_payload vista_source_key
]

scope = Habitation
  .includes(:proprietor, :admin_user, broker_assignments: :admin_user)
  .where.not(vista_codigo: [nil, ""])
  .where("vista_codigo ~ ?", "^[0-9]+$")
  .order(Arel.sql("vista_codigo::bigint ASC"))
scope = scope.limit(limit) if limit

count = 0

File.open(output_path, "w") do |file|
  scope.find_each(batch_size: 250) do |habitation|
    proprietor = habitation.proprietor

    row = {
      vista_codigo: habitation.vista_codigo.to_s,
      local_codigo: habitation.codigo.to_s,
      habitation_attributes: habitation.attributes.except(*excluded_habitation_columns),
      admin_user_vista_id: habitation.admin_user&.vista_id,
      admin_user_email: habitation.admin_user&.email,
      proprietor: proprietor && {
        vista_code: proprietor.vista_code,
        attributes: proprietor.attributes.except(*excluded_proprietor_columns)
      },
      broker_assignments: habitation.broker_assignments.map do |assignment|
        {
          admin_user_vista_id: assignment.admin_user&.vista_id,
          admin_user_email: assignment.admin_user&.email,
          attributes: assignment.attributes.except(*excluded_assignment_columns)
        }
      end
    }

    file.puts(row.to_json)
    count += 1
  end
end

puts({ output: output_path, exported: count }.to_json)
