require "csv"

module Whatsapp
  class CampaignSpreadsheetImporter
    Row = Struct.new(:recipient, :lead, :name, :phone, :email, :origin, :status, :tags, :admin_user_id, :errors, keyword_init: true) do
      def valid?
        errors.blank?
      end

      def display_name
        recipient&.display_name || lead&.display_name || name
      end

      def display_phone
        recipient&.display_phone || lead&.display_phone || phone
      end

      def display_email
        recipient&.display_email || lead&.display_email || email
      end
    end

    Result = Struct.new(:rows, :valid_rows, :invalid_rows, :recipients, :errors, keyword_init: true) do
      def total
        rows.size
      end

      def valid_phone_count
        valid_rows.size
      end

      def without_phone_count
        invalid_rows.count { |row| row.errors.include?("telefone ausente") }
      end
    end

    HEADER_ALIASES = {
      name: %w[nome name cliente lead cliente_nome nome_do_lead],
      phone: %w[telefone phone celular whatsapp numero número contato],
      email: %w[email e-mail mail],
      origin: %w[origem origin canal fonte],
      status: %w[status etapa funil],
      tags: %w[tags tag etiquetas etiqueta marcadores marcador],
      admin_user_id: %w[responsavel_id corretor_id admin_user_id],
      admin_user_email: %w[responsavel_email corretor_email email_responsavel email_corretor],
      admin_user_name: %w[responsavel corretor nome_responsavel nome_corretor]
    }.freeze

    def self.call(campaign:, materialize: false, uploaded_file: nil)
      new(campaign:, materialize:, uploaded_file:).call
    end

    def initialize(campaign:, materialize:, uploaded_file:)
      @campaign = campaign
      @materialize = materialize
      @uploaded_file = uploaded_file
    end

    def call
      ensure_supported_file!
      parsed_rows = parse_csv
      rows = parsed_rows.each_with_index.map { |data, index| build_row(data, index + 2) }
      valid_rows = dedupe_rows(rows.select(&:valid?))
      recipients = materialize ? materialize_rows(valid_rows) : []
      Result.new(rows:, valid_rows:, invalid_rows: rows.reject(&:valid?), recipients:, errors: [])
    rescue => e
      Result.new(rows: [], valid_rows: [], invalid_rows: [], recipients: [], errors: [e.message])
    end

    private

    attr_reader :campaign, :materialize, :uploaded_file

    def ensure_supported_file!
      raise ArgumentError, "Envie um arquivo CSV para importar destinatários." unless source_file_present?

      filename = source_filename.downcase
      return if filename.end_with?(".csv")

      raise ArgumentError, "Importação XLS/XLSX ainda não está habilitada neste ambiente. Exporte a planilha como CSV."
    end

    def parse_csv
      read_csv(col_sep: nil)
    rescue CSV::MalformedCSVError
      read_csv(col_sep: ";")
    end

    def read_csv(col_sep:)
      options = { headers: true, encoding: "bom|utf-8" }
      options[:col_sep] = col_sep if col_sep.present?

      if uploaded_file.present?
        CSV.read(uploaded_file.tempfile.path, **options).map(&:to_h)
      else
        campaign.audience_file.open { |file| CSV.read(file.path, **options).map(&:to_h) }
      end
    end

    def source_file_present?
      uploaded_file.present? || campaign.audience_file.attached?
    end

    def source_filename
      return uploaded_file.original_filename.to_s if uploaded_file.present?

      campaign.audience_file.filename.to_s
    end

    def build_row(data, line_number)
      normalized = normalize_data(data)
      phone = Phones::Normalizer.call(normalized[:phone]).to_s
      admin_user = resolve_admin_user(normalized)
      errors = []
      errors << "telefone ausente" if phone.blank?

      Row.new(
        name: normalized[:name].presence || "Contato importado #{phone.presence || line_number}",
        phone: phone,
        email: normalized[:email],
        origin: normalized[:origin].presence || "importacao",
        status: normalized[:status].presence || Lead.default_status,
        tags: Lead.normalize_tags_value(normalized[:tags]),
        admin_user_id: admin_user&.id,
        errors:
      )
    end

    def normalize_data(data)
      normalized_headers = data.transform_keys { |key| normalize_header(key) }
      HEADER_ALIASES.each_with_object({}) do |(target, aliases), result|
        key = aliases.find { |candidate| normalized_headers.key?(candidate) }
        result[target] = normalized_headers[key].to_s.strip if key
      end
    end

    def normalize_header(value)
      value.to_s.downcase.strip
           .tr("áàãâäéèêëíìîïóòõôöúùûüç", "aaaaaeeeeiiiiooooouuuuc")
           .gsub(/[^a-z0-9]+/, "_")
           .gsub(/\A_+|_+\z/, "")
    end

    def dedupe_rows(rows)
      rows.uniq { |row| row.phone }
    end

    def materialize_rows(rows)
      rows.map do |row|
        recipient = campaign.campaign_recipients.find_or_initialize_by(phone_number: row.phone)
        recipient.assign_attributes(
          source: "spreadsheet",
          lead: find_existing_lead(row.phone),
          name: row.name,
          email: row.email,
          origin: row.origin,
          status: row.status,
          tags: row.tags,
          admin_user_id: row.admin_user_id,
          conversion_status: recipient.conversion_status.presence || "pending"
        )
        recipient.save!
        row.recipient = recipient
      end
    end

    def find_existing_lead(phone)
      tail = phone.to_s.last(11)
      campaign.tenant.leads.where("regexp_replace(coalesce(phone, ''), '\\D', '', 'g') LIKE ?", "%#{tail}").first
    end

    def resolve_admin_user(data)
      id = Integer(data[:admin_user_id], exception: false)
      return campaign.tenant.admin_users.active.find_by(id:) if id

      email = data[:admin_user_email].to_s.strip
      return campaign.tenant.admin_users.active.find_by("LOWER(email) = ?", email.downcase) if email.present?

      name = data[:admin_user_name].to_s.strip
      return if name.blank?

      campaign.tenant.admin_users.active.find_by("LOWER(name) = ?", name.downcase)
    end
  end
end
