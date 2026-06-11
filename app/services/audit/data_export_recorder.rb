module Audit
  class DataExportRecorder
    SENSITIVE_KEYS = /email|phone|fone|cpf|cnpj|document|spouse|name|nome/i

    def self.call(...)
      new(...).call
    end

    def initialize(admin_user:, request:, export_type:, resource_name:, format:, record_count:, selected_count: 0, filename: nil, filters: {}, fields: [], metadata: {})
      @admin_user = admin_user
      @request = request
      @export_type = export_type
      @resource_name = resource_name
      @format = format
      @record_count = record_count.to_i
      @selected_count = selected_count.to_i
      @filename = filename
      @filters = filters || {}
      @fields = fields || []
      @metadata = metadata || {}
    end

    def call
      DataExportAuditLog.create!(
        admin_user: admin_user,
        export_type: export_type,
        resource_name: resource_name,
        format: format,
        record_count: record_count,
        selected_count: selected_count,
        filename: filename,
        filters: sanitized_hash(filters),
        fields: Array(fields).map(&:to_s),
        metadata: sanitized_hash(request_metadata.merge(metadata)),
        ip: request&.remote_ip,
        user_agent: request&.user_agent.to_s.first(255)
      )
    rescue => e
      Rails.logger.warn("[DataExportAuditLog] #{e.class}: #{e.message}")
      nil
    end

    private

    attr_reader :admin_user, :request, :export_type, :resource_name, :format, :record_count, :selected_count, :filename, :filters, :fields, :metadata

    def request_metadata
      return {} unless request

      {
        path: request.fullpath,
        method: request.request_method,
        controller: request.params[:controller],
        action: request.params[:action]
      }
    end

    def sanitized_hash(value)
      value.to_h.each_with_object({}) do |(key, val), result|
        result[key.to_s] = sanitized_value(key, val)
      end
    rescue
      {}
    end

    def sanitized_value(key, value)
      return value.map { |item| sanitized_value(key, item) } if value.is_a?(Array)
      return sanitized_hash(value) if value.respond_to?(:to_h) && !value.is_a?(String)
      return "[filtrado]" if key.to_s.match?(SENSITIVE_KEYS) && value.present?

      value
    end
  end
end
