module Habitations
  class DevelopmentNameReconciliationService
    DEFAULT_MAPPINGS = {
      "8911" => "Lá Belle Verte",
      "8913" => "Lá Belle Verte",
      "8949" => "Torremolinos",
      "8950" => "Torremolinos",
      "8988" => "Torremolinos"
    }.freeze

    Result = Struct.new(:codigo, :status, :before_name, :before_code, :after_name, :message, keyword_init: true)

    attr_reader :tenant, :mappings, :dry_run, :results

    def initialize(tenant:, mappings: DEFAULT_MAPPINGS, dry_run: true)
      @tenant = tenant || raise(ArgumentError, "Tenant obrigatório")
      @mappings = mappings.transform_keys(&:to_s).transform_values { |name| name.to_s.strip }
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @results = []
    end

    def call
      mappings.each do |codigo, name|
        reconcile(codigo, name)
      end

      self
    end

    def stats
      results.group_by(&:status).transform_values(&:count).reverse_merge(
        updated: 0,
        would_update: 0,
        skipped_existing_development: 0,
        skipped_blank_mapping: 0,
        not_found: 0,
        error: 0
      )
    end

    private

    def reconcile(codigo, name)
      if name.blank?
        add_result(codigo, :skipped_blank_mapping, message: "Nome de empreendimento em branco no mapeamento")
        return
      end

      habitation = tenant.habitations.find_by(codigo: codigo)
      unless habitation
        add_result(codigo, :not_found, after_name: name, message: "Imóvel não encontrado no tenant #{tenant.id}")
        return
      end

      before_name = habitation.nome_empreendimento
      before_code = habitation.codigo_empreendimento

      if before_name.present? || before_code.present?
        add_result(
          codigo,
          :skipped_existing_development,
          before_name: before_name,
          before_code: before_code,
          after_name: name,
          message: "Imóvel já possui nome ou código de empreendimento"
        )
        return
      end

      if dry_run
        add_result(codigo, :would_update, before_name: before_name, before_code: before_code, after_name: name)
        return
      end

      Habitation.transaction do
        habitation.lock!
        before_name = habitation.nome_empreendimento
        before_code = habitation.codigo_empreendimento

        if before_name.present? || before_code.present?
          add_result(
            codigo,
            :skipped_existing_development,
            before_name: before_name,
            before_code: before_code,
            after_name: name,
            message: "Imóvel recebeu nome ou código de empreendimento antes da aplicação"
          )
          return
        end

        habitation.skip_auto_audit = true
        habitation.update!(nome_empreendimento: name)

        record_audit!(habitation, before_name, name)
        add_result(codigo, :updated, before_name: before_name, before_code: before_code, after_name: name)
      end
    rescue => e
      add_result(codigo, :error, after_name: name, message: "#{e.class}: #{e.message}")
    end

    def record_audit!(habitation, before_name, after_name)
      Habitations::AuditChangeRecorder.new(
        habitation,
        actor: nil,
        source: "sistema",
        metadata: {
          service: self.class.name,
          reconciliation: "pontual_development_name",
          tenant_id: tenant.id
        }
      ).record_bulk_update!(
        {
          "nome_empreendimento" => {
            before: before_name,
            after: after_name
          }
        }
      )
    end

    def add_result(codigo, status, before_name: nil, before_code: nil, after_name: nil, message: nil)
      results << Result.new(
        codigo: codigo,
        status: status,
        before_name: before_name,
        before_code: before_code,
        after_name: after_name,
        message: message
      )
    end
  end
end
