module Habitations
  class AuditChangeRecorder
    TECHNICAL_FIELDS = %w[id created_at updated_at].freeze
    ADDRESS_TECHNICAL_FIELDS = %w[id addressable_id addressable_type created_at updated_at].freeze
    ADMIN_NOISE_FIELDS = %w[
      agenciador
      data_atualizacao_crm
      imovel_dwv
      perfil_construcao
      pictures
      photo_ids_order
      tipo_vaga
    ].freeze
    ATTACHMENT_ASSOCIATIONS = %w[photos fichas_cadastro autorizacoes_venda].freeze
    BROKER_ASSIGNMENT_FIELDS = %w[
      id admin_user_id admin_user_name role commission_type commission_value observations
    ].freeze

    def self.snapshot_for(habitation)
      {
        "attributes" => habitation_attributes(habitation),
        "address" => address_attributes(habitation.address),
        "attachments" => attachment_attributes(habitation),
        "broker_assignments" => broker_assignment_attributes(habitation)
      }
    end

    def self.habitation_attributes(habitation)
      audited_habitation_fields.index_with { |field| normalize_value(habitation.read_attribute(field)) }
    end

    def self.address_attributes(address)
      return {} unless address

      audited_address_fields.index_with { |field| normalize_value(address.read_attribute(field)) }
    end

    def self.attachment_attributes(habitation)
      ATTACHMENT_ASSOCIATIONS.index_with do |association|
        habitation.public_send(association).attachments.includes(:blob).map do |attachment|
          attachment_payload(attachment)
        end.sort_by { |payload| payload["id"].to_i }
      end
    end

    def self.broker_assignment_attributes(habitation)
      habitation.broker_assignments.includes(:admin_user).map do |assignment|
        {
          "id" => assignment.id,
          "admin_user_id" => assignment.admin_user_id,
          "admin_user_name" => assignment.admin_user&.name.presence || assignment.admin_user&.email,
          "role" => assignment.role,
          "commission_type" => assignment.commission_type,
          "commission_value" => normalize_value(assignment.commission_value),
          "observations" => assignment.observations
        }
      end.sort_by { |payload| payload["id"].to_i }
    end

    def self.audited_habitation_fields
      Habitation.column_names - TECHNICAL_FIELDS
    end

    def self.audited_address_fields
      Address.column_names - ADDRESS_TECHNICAL_FIELDS
    end

    def self.attachment_payload(attachment)
      {
        "id" => attachment.id,
        "filename" => attachment.filename.to_s,
        "content_type" => attachment.content_type,
        "byte_size" => attachment.byte_size
      }
    end

    def self.normalize_value(value)
      case value
      when BigDecimal
        value.to_s("F")
      when Time, Date, DateTime
        value.iso8601
      when ActiveSupport::SafeBuffer
        value.to_s
      else
        value
      end
    end

    def initialize(habitation, actor:, request: nil, source: "admin", before_snapshot: nil, metadata: {}, ignored_fields: [])
      @habitation = habitation
      @actor = actor
      @request = request
      @source = source
      @before_snapshot = before_snapshot
      @metadata = metadata
      @ignored_fields = Array(ignored_fields).map(&:to_s)
    end

    def record_create!
      changeset = creation_changeset

      create_log!(
        action: "created",
        changeset: changeset,
        metadata: metadata
      )
    end

    def record_update!
      changeset = normalized_changes
      return if changeset.blank?

      create_log!(
        action: infer_action(changeset),
        changeset: changeset,
        metadata: metadata
      )
    end

    def record_destroy!
      changeset = destruction_changeset(before_snapshot || self.class.snapshot_for(habitation))

      create_log!(
        action: "deleted",
        changeset: changeset,
        metadata: metadata
      )
    end

    def record_bulk_update!(changeset, metadata: {})
      normalized = normalize_changeset(changeset)
      return if normalized.blank?

      create_log!(
        action: "bulk_updated",
        changeset: normalized,
        metadata: self.metadata.merge(metadata)
      )
    end

    def record_attachment_removed!(association:, attachment_payload:)
      field = attachment_field(association)
      before_value = Array(current_snapshot.dig("attachments", association.to_s))
      after_value = before_value.reject { |payload| payload["id"].to_i == attachment_payload["id"].to_i }

      create_log!(
        action: "attachments_changed",
        changeset: { field => { before: before_value, after: after_value } },
        metadata: metadata.merge(association: association.to_s, attachment_id: attachment_payload["id"])
      )
    end

    private

    attr_reader :habitation, :actor, :request, :source, :before_snapshot, :metadata, :ignored_fields

    def normalized_changes
      changeset = model_changes.merge(snapshot_changes)
      normalize_changeset(changeset)
    end

    def model_changes
      habitation_changes.merge(address_changes)
    end

    def habitation_changes
      habitation.previous_changes.each_with_object({}) do |(field, values), result|
        next unless self.class.audited_habitation_fields.include?(field.to_s)

        result[field.to_s] = change_payload(values)
      end
    end

    def address_changes
      address = habitation.address
      return {} unless address

      address.previous_changes.each_with_object({}) do |(field, values), result|
        next unless self.class.audited_address_fields.include?(field.to_s)

        result["address.#{field}"] = change_payload(values)
      end
    end

    def snapshot_changes
      return {} if before_snapshot.blank?

      after_snapshot = current_snapshot
      attachment_changes(before_snapshot, after_snapshot)
        .merge(broker_assignment_changes(before_snapshot, after_snapshot))
        .merge(address_snapshot_changes(before_snapshot, after_snapshot))
    end

    def attachment_changes(before, after)
      ATTACHMENT_ASSOCIATIONS.each_with_object({}) do |association, result|
        before_value = Array(before.dig("attachments", association))
        after_value = Array(after.dig("attachments", association))
        next if before_value == after_value

        result[attachment_field(association)] = { before: before_value, after: after_value }
      end
    end

    def broker_assignment_changes(before, after)
      before_value = Array(before["broker_assignments"])
      after_value = Array(after["broker_assignments"])
      return {} if before_value == after_value

      { "broker_assignments" => { before: before_value, after: after_value } }
    end

    def address_snapshot_changes(before, after)
      before_address = before["address"].to_h
      after_address = after["address"].to_h

      self.class.audited_address_fields.each_with_object({}) do |field, result|
        before_value = before_address[field]
        after_value = after_address[field]
        next if before_value == after_value
        next if result.key?("address.#{field}")

        result["address.#{field}"] = { before: before_value, after: after_value }
      end
    end

    def creation_changeset
      snapshot_to_changeset(current_snapshot, before_value: nil)
    end

    def destruction_changeset(snapshot)
      snapshot_to_changeset(snapshot, after_value: nil)
    end

    def snapshot_to_changeset(snapshot, before_value: :__current__, after_value: :__current__)
      changeset = {}

      snapshot.fetch("attributes", {}).each do |field, value|
        next if blank_created_value?(before_value, value)

        changeset[field] = {
          before: before_value == :__current__ ? value : before_value,
          after: after_value == :__current__ ? value : after_value
        }
      end

      snapshot.fetch("address", {}).each do |field, value|
        next if blank_created_value?(before_value, value)

        changeset["address.#{field}"] = {
          before: before_value == :__current__ ? value : before_value,
          after: after_value == :__current__ ? value : after_value
        }
      end

      snapshot.fetch("attachments", {}).each do |association, value|
        next if blank_created_value?(before_value, value)

        changeset[attachment_field(association)] = {
          before: before_value == :__current__ ? value : before_value,
          after: after_value == :__current__ ? value : after_value
        }
      end

      broker_assignments = snapshot.fetch("broker_assignments", [])
      unless blank_created_value?(before_value, broker_assignments)
        changeset["broker_assignments"] = {
          before: before_value == :__current__ ? broker_assignments : before_value,
          after: after_value == :__current__ ? broker_assignments : after_value
        }
      end

      changeset
    end

    def blank_created_value?(before_value, value)
      before_value.nil? && (value.nil? || value == "" || value == [] || value == {})
    end

    def normalize_changeset(changeset)
      changeset.each_with_object({}) do |(field, values), result|
        before_value = values.is_a?(Hash) ? fetch_change_value(values, :before) : nil
        after_value = values.is_a?(Hash) ? fetch_change_value(values, :after) : nil
        before_value = self.class.normalize_value(before_value)
        after_value = self.class.normalize_value(after_value)
        field_name = field.to_s
        next if ignored_fields.include?(field_name)
        next if semantically_equal?(field_name, before_value, after_value)

        result[field_name] = { before: before_value, after: after_value }
      end
    end

    def semantically_equal?(field, before_value, after_value)
      audit_value_for_compare(field, before_value) == audit_value_for_compare(field, after_value)
    end

    def audit_value_for_compare(field, value)
      case value
      when nil
        nil
      when String
        normalized = value.strip
        return normalized.gsub(/\D/, "").presence if phone_field?(field)

        normalized.presence
      when Array
        normalized = value.map { |item| audit_value_for_compare(field, item) }.compact
        normalized.presence
      when Hash
        normalized = value.to_h.transform_values { |item| audit_value_for_compare(field, item) }.reject { |_key, item| item.nil? }
        normalized.presence
      else
        value
      end
    end

    def phone_field?(field)
      field.to_s.match?(/telefone|celular/)
    end

    def fetch_change_value(values, key)
      values.key?(key) ? values[key] : values[key.to_s]
    end

    def change_payload(values)
      before, after = values
      { before: self.class.normalize_value(before), after: self.class.normalize_value(after) }
    end

    def infer_action(changeset)
      if changeset.keys.any? { |field| field.end_with?("_attachments") }
        return "attachments_changed"
      end

      return "broker_assignments_changed" if changeset.key?("broker_assignments")

      if changeset.key?("exibir_no_site_flag")
        return changeset.dig("exibir_no_site_flag", :after) ? "published" : "unpublished"
      end

      return "intake_status_changed" if changeset.key?("intake_status")

      "updated"
    end

    def create_log!(action:, changeset:, metadata:)
      HabitationAuditLog.create!(
        habitation: habitation,
        admin_user: actor,
        action: action,
        source: source,
        changed_fields: changeset.keys,
        changeset: changeset,
        metadata: request_metadata.merge(metadata),
        ip: request&.remote_ip || Current.request_ip,
        user_agent: (request&.user_agent || Current.request_user_agent).to_s.first(255)
      )
    end

    def current_snapshot
      self.class.snapshot_for(habitation.reload)
    end

    def attachment_field(association)
      "#{association}_attachments"
    end

    def request_metadata
      return Current.request_metadata.to_h.compact unless request

      {
        path: request.fullpath,
        method: request.request_method,
        controller: request.params[:controller],
        action: request.params[:action]
      }.compact
    end
  end
end
