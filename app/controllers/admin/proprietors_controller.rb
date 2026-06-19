module Admin
  class ProprietorsController < BaseController
    require "csv"
    before_action -> { check_permission!(:view, :proprietarios) }
    before_action -> { check_permission!(:manage, :proprietarios) }, only: %i[new create edit update destroy quick_create]

    EXPORT_FIELDS = {
      "name" => "Nome/Denominação",
      "role" => "Tipo",
      "vista_code" => "Código",
      "email" => "Email",
      "phone_primary" => "Fone principal",
      "residential_phone" => "Fone residencial",
      "business_phone" => "Fone comercial",
      "mobile_phone" => "Celular",
      "cpf_cnpj" => "CPF/CNPJ",
      "city" => "Cidade",
      "capture_vehicle" => "Veículo de captação",
      "habitation_code" => "Imovel.Codigo",
      "habitation_brokers" => "Imovel.Corretores do Imovel",
      "habitation_rent" => "Imovel.Valor Aluguel",
      "habitation_sale" => "Imovel.Valor Venda",
      "habitation_status" => "Imovel.Status",
      "habitation_category" => "Imovel.Categoria"
    }.freeze

    REPORT_TYPES = {
      "proprietors" => "Listagem de proprietários",
      "proprietors_with_habitations" => "Listagem de proprietários com imóveis"
    }.freeze

    before_action :set_proprietor, only: %i[edit update destroy]

    def index
      @filters = proprietor_filter_params.to_h.symbolize_keys
      @proprietors = filtered_proprietors_scope
                    .paginate(page: params[:page], per_page: 20)
      @habitations_count_by_proprietor = Habitation.where(proprietor_id: @proprietors.map(&:id)).group(:proprietor_id).count

      @capture_vehicle_options = Proprietor::CAPTURE_VEHICLES
      @name_options = Proprietor.where.not(name: [nil, ""]).distinct.order(:name).pluck(:name)
      @city_options = Proprietor.where.not(city: [nil, ""]).distinct.order(:city).pluck(:city)
      @email_options = Proprietor.where.not(email: [nil, ""]).distinct.order(:email).pluck(:email)
      @phone_options = Proprietor
        .pluck(:phone_primary, :mobile_phone, :residential_phone, :business_phone)
        .flatten
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
        .uniq
        .sort
      @spouse_name_options = Proprietor.where.not(spouse_name: [nil, ""]).distinct.order(:spouse_name).pluck(:spouse_name)
      @spouse_email_options = Proprietor.where.not(spouse_email: [nil, ""]).distinct.order(:spouse_email).pluck(:spouse_email)
      @spouse_phone_options = Proprietor.where.not(spouse_phone: [nil, ""]).distinct.order(:spouse_phone).pluck(:spouse_phone)

      reference_codes = Habitation.where.not(codigo: [nil, ""]).distinct.order(:codigo).limit(200).pluck(:codigo)
      reference_titles = Habitation.where.not(titulo_anuncio: [nil, ""]).distinct.order(:titulo_anuncio).limit(200).pluck(:titulo_anuncio)
      reference_developments = Habitation.where.not(nome_empreendimento: [nil, ""]).distinct.order(:nome_empreendimento).limit(200).pluck(:nome_empreendimento)
      @habitation_reference_options = (reference_codes + reference_titles + reference_developments).map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort
      @habitation_address_options = Habitation.where.not(endereco: [nil, ""]).distinct.order(:endereco).limit(400).pluck(:endereco)
      @habitation_number_options = Habitation.where.not(numero: [nil, ""]).distinct.order(:numero).limit(300).pluck(:numero)

      @habitation_category_options = Habitation.where.not(categoria: [nil, ""]).distinct.order(:categoria).pluck(:categoria)
      @habitation_status_options = Habitation.where.not(status: [nil, ""]).distinct.order(:status).pluck(:status)
      @export_fields = EXPORT_FIELDS
      @report_types = REPORT_TYPES
      @default_export_fields = %w[name phone_primary residential_phone business_phone mobile_phone habitation_code habitation_brokers habitation_rent]
    end

    def print
      @filters = proprietor_filter_params.to_h.symbolize_keys
      @report_type = normalized_report_type
      @proprietors = filtered_proprietors_scope
      ids = sanitized_selected_ids
      @proprietors = @proprietors.where(id: ids) if ids.any?

      if @report_type == "proprietors_with_habitations"
        @rows = @proprietors.flat_map do |proprietor|
          habitations = proprietor.habitations.order(updated_at: :desc)
          habitations.any? ? habitations.map { |habitation| [proprietor, habitation] } : [[proprietor, nil]]
        end
      end

      record_data_export!(
        export_type: "print_report",
        format: "html_print",
        record_count: @report_type == "proprietors_with_habitations" ? @rows.size : @proprietors.count,
        selected_count: ids.size,
        fields: [@report_type],
        filters: data_export_filters,
        metadata: { report_type: @report_type }
      )

      render layout: false
    end

    def export
      filters = proprietor_filter_params.to_h.symbolize_keys
      report_type = normalized_report_type
      fields = sanitized_export_fields
      data_format = normalized_data_format
      proprietors = apply_index_filters(Proprietor.left_outer_joins(:habitations), filters).distinct.order(name: :asc)
      ids = sanitized_selected_ids
      proprietors = proprietors.where(id: ids) if ids.any?

      csv_content = CSV.generate(headers: true, col_sep: data_format == "csv_semicolon" ? ";" : ",") do |csv|
        csv << fields.map { |field| EXPORT_FIELDS[field] || field }

        if report_type == "proprietors_with_habitations"
          proprietors.each do |proprietor|
            habitations = proprietor.habitations.order(updated_at: :desc)
            if habitations.any?
              habitations.each do |habitation|
                csv << export_row(fields, proprietor, habitation)
              end
            else
              csv << export_row(fields, proprietor, nil)
            end
          end
        else
          proprietors.each do |proprietor|
            csv << export_row(fields, proprietor, proprietor.habitations.order(updated_at: :desc).first)
          end
        end
      end

      record_count = report_type == "proprietors_with_habitations" ? export_rows_count(proprietors) : proprietors.count
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "proprietarios_#{report_type}_#{timestamp}.csv"
      record_data_export!(
        export_type: "csv_export",
        format: data_format,
        record_count: record_count,
        selected_count: ids.size,
        filename: filename,
        fields: fields,
        filters: data_export_filters,
        metadata: { report_type: report_type }
      )

      send_data csv_content,
                filename: filename,
                type: "text/csv; charset=utf-8"
    end

    def new
      @proprietor = Proprietor.new
    end

    def edit
      load_habitations
    end

    def create
      @proprietor = Proprietor.new(proprietor_params)

      if @proprietor.save
        redirect_to admin_proprietors_path, notice: "Proprietário criado com sucesso."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def quick_create
      permitted = quick_proprietor_params
      phone = permitted[:mobile_phone].presence || permitted[:phone_primary].presence
      @proprietor = Proprietor.find_by_phone(phone) if phone.present?
      @proprietor ||= Proprietor.new(role: :owner)

      @proprietor.name = permitted[:name] if permitted[:name].present?
      @proprietor.email = permitted[:email] if permitted[:email].present?
      @proprietor.phone_primary = permitted[:phone_primary] if permitted[:phone_primary].present?
      @proprietor.mobile_phone = permitted[:mobile_phone] if permitted[:mobile_phone].present?
      @proprietor.cpf_cnpj = permitted[:cpf_cnpj] if permitted[:cpf_cnpj].present?

      if @proprietor.save
        render json: { id: @proprietor.id, name: @proprietor.select_label }, status: :created
      else
        render json: { errors: @proprietor.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @proprietor.update(proprietor_params)
        redirect_to admin_proprietors_path, notice: "Proprietário atualizado com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @proprietor.destroy
      redirect_to admin_proprietors_path, notice: "Proprietário excluído com sucesso."
    end

    private

    def set_proprietor
      @proprietor = Proprietor.find_by(id: params[:id])
      return if @proprietor.present?

      # Compatibilidade com links legados do módulo de construtoras.
      legacy_constructor = Constructor.find_by(id: params[:id]) if defined?(Constructor)
      if legacy_constructor.present?
        @proprietor = Proprietor.find_or_create_by!(name: legacy_constructor.name) do |p|
          p.role = :builder
        end
        redirect_to edit_admin_proprietor_path(@proprietor), notice: "Cadastro legado convertido para Proprietário."
        return
      end

      redirect_to admin_proprietors_path, alert: "Proprietário não encontrado."
    end

    def require_admin_or_administrative!
      return if current_admin_user&.admin? || current_admin_user&.profile&.administrativo?

      redirect_to admin_root_path, alert: "Acesso negado. Apenas administradores."
    end

    def proprietor_params
      params.require(:proprietor).permit(
        :name, :role, :vista_code, :cpf_cnpj, :rg_ie, :issuing_authority,
        :birth_date, :email, :phone_primary, :mobile_phone, :residential_phone,
        :business_phone, :phone_extension, :profession, :marital_status,
        :marriage_regime, :nationality, :capture_vehicle, :registered_at,
        :spouse_name, :spouse_email, :spouse_phone, :spouse_cpf_cnpj,
        :notes, :is_client, :address_type, :street, :number, :complement,
        :block, :uf, :cep, :neighborhood, :city, :profile_image
      )
    end

    def quick_proprietor_params
      params.require(:proprietor).permit(
        :name,
        :email,
        :phone_primary,
        :mobile_phone,
        :cpf_cnpj
      )
    end

    def proprietor_filter_params
      params.fetch(:filters, {}).permit(
        :vista_code, :registered_at, :name, :email, :phone, :cpf_cnpj, :capture_vehicle, :city,
        :spouse_name, :spouse_email, :spouse_phone, :spouse_cpf_cnpj,
        :habitation_reference, :habitation_registered_at, :habitation_updated_at,
        :habitation_address, :habitation_number, :habitation_category, :habitation_status
      )
    end

    def filtered_proprietors_scope
      apply_index_filters(Proprietor.left_outer_joins(:habitations), @filters)
        .distinct
        .order(name: :asc)
    end

    def apply_index_filters(scope, filters = @filters)
      filters ||= {}

      if filters[:vista_code].present?
        scope = scope.where("proprietors.vista_code ILIKE ?", like(filters[:vista_code]))
      end

      if (date = parse_date(filters[:registered_at]))
        scope = scope.where("proprietors.registered_at = ?", date)
      end

      if filters[:name].present?
        scope = scope.where("proprietors.name ILIKE ?", like(filters[:name]))
      end

      if filters[:email].present?
        scope = scope.where("proprietors.email ILIKE ?", like(filters[:email]))
      end

      if filters[:phone].present?
        phone_like = like(filters[:phone])
        scope = scope.where(
          "proprietors.phone_primary ILIKE :q OR proprietors.mobile_phone ILIKE :q OR " \
          "proprietors.residential_phone ILIKE :q OR proprietors.business_phone ILIKE :q",
          q: phone_like
        )
      end

      if filters[:cpf_cnpj].present?
        scope = scope.where("proprietors.cpf_cnpj ILIKE ?", like(filters[:cpf_cnpj]))
      end

      if filters[:capture_vehicle].present?
        scope = scope.where(capture_vehicle: filters[:capture_vehicle])
      end

      if filters[:city].present?
        scope = scope.where("proprietors.city ILIKE ?", like(filters[:city]))
      end

      if filters[:spouse_name].present?
        scope = scope.where("proprietors.spouse_name ILIKE ?", like(filters[:spouse_name]))
      end

      if filters[:spouse_email].present?
        scope = scope.where("proprietors.spouse_email ILIKE ?", like(filters[:spouse_email]))
      end

      if filters[:spouse_phone].present?
        scope = scope.where("proprietors.spouse_phone ILIKE ?", like(filters[:spouse_phone]))
      end

      if filters[:spouse_cpf_cnpj].present?
        scope = scope.where("proprietors.spouse_cpf_cnpj ILIKE ?", like(filters[:spouse_cpf_cnpj]))
      end

      if filters[:habitation_reference].present?
        ref_like = like(filters[:habitation_reference])
        scope = scope.where(
          "habitations.codigo ILIKE :q OR habitations.titulo_anuncio ILIKE :q OR habitations.nome_empreendimento ILIKE :q",
          q: ref_like
        )
      end

      if (date = parse_date(filters[:habitation_registered_at]))
        scope = scope.where("DATE(COALESCE(habitations.data_cadastro_crm, habitations.created_at)) = ?", date)
      end

      if (date = parse_date(filters[:habitation_updated_at]))
        scope = scope.where("DATE(COALESCE(habitations.data_atualizacao_crm, habitations.updated_at)) = ?", date)
      end

      if filters[:habitation_address].present?
        scope = scope.where("habitations.endereco ILIKE ?", like(filters[:habitation_address]))
      end

      if filters[:habitation_number].present?
        scope = scope.where("habitations.numero ILIKE ?", like(filters[:habitation_number]))
      end

      if filters[:habitation_category].present?
        scope = scope.where(habitations: { categoria: filters[:habitation_category] })
      end

      if filters[:habitation_status].present?
        scope = scope.where(habitations: { status: filters[:habitation_status] })
      end

      scope
    end

    def export_row(fields, proprietor, habitation)
      fields.map { |field| export_field_value(field, proprietor, habitation) }
    end

    def export_field_value(field, proprietor, habitation)
      case field
      when "name" then proprietor.name
      when "role" then proprietor.display_role
      when "vista_code" then proprietor.vista_code
      when "email" then proprietor.email
      when "phone_primary" then proprietor.phone_primary
      when "residential_phone" then proprietor.residential_phone
      when "business_phone" then proprietor.business_phone
      when "mobile_phone" then proprietor.mobile_phone
      when "cpf_cnpj" then proprietor.cpf_cnpj
      when "city" then proprietor.city
      when "capture_vehicle" then proprietor.capture_vehicle
      when "habitation_code" then habitation&.codigo
      when "habitation_brokers" then habitation&.corretor_nome
      when "habitation_rent" then money_from_cents(habitation&.valor_locacao_cents)
      when "habitation_sale" then money_from_cents(habitation&.valor_venda_cents)
      when "habitation_status" then habitation&.status
      when "habitation_category" then habitation&.categoria
      else
        nil
      end
    end

    def sanitized_export_fields
      fields = Array(params[:fields]).map(&:to_s)
      fields = %w[name phone_primary] if fields.empty?
      selected = fields.select { |field| EXPORT_FIELDS.key?(field) }
      selected.presence || %w[name phone_primary]
    end

    def normalized_report_type
      report_type = params[:report_type].to_s
      REPORT_TYPES.key?(report_type) ? report_type : "proprietors"
    end

    def normalized_data_format
      %w[csv csv_semicolon].include?(params[:data_format].to_s) ? params[:data_format].to_s : "csv"
    end

    def sanitized_selected_ids
      raw_ids = params[:selected_ids]
      values = if raw_ids.is_a?(String)
                 raw_ids.split(",")
               else
                 Array(raw_ids)
               end

      values.map { |value| value.to_s.strip }
            .reject(&:blank?)
            .map(&:to_i)
            .select { |id| id.positive? }
            .uniq
    end

    def record_data_export!(export_type:, format:, record_count:, selected_count:, fields:, filters:, filename: nil, metadata: {})
      Audit::DataExportRecorder.call(
        admin_user: current_admin_user,
        request: request,
        export_type: export_type,
        resource_name: "proprietors",
        format: format,
        record_count: record_count,
        selected_count: selected_count,
        filename: filename,
        filters: filters,
        fields: fields,
        metadata: metadata
      )
    end

    def data_export_filters
      params.to_unsafe_h.slice("filters", "selected_ids", "report_type", "data_format", "fields")
    end

    def export_rows_count(proprietors)
      proprietors.sum do |proprietor|
        count = proprietor.habitations.count
        count.positive? ? count : 1
      end
    end

    def money_from_cents(cents)
      value = cents.to_i
      return nil if value <= 0

      ActiveSupport::NumberHelper.number_to_currency(value / 100.0, unit: "R$ ", separator: ",", delimiter: ".")
    end

    def like(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%"
    end

    def parse_date(value)
      return if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def load_habitations
      @habitation_q = params[:habitation_q].to_s.strip
      @habitation_status = params[:habitation_status].to_s.strip

      scope = @proprietor.habitations.left_outer_joins(:address).order(updated_at: :desc)
      if @habitation_q.present?
        query = "%#{@habitation_q}%"
        scope = scope.where(
          "habitations.codigo ILIKE :q OR habitations.titulo_anuncio ILIKE :q OR " \
          "COALESCE(addresses.bairro, habitations.bairro) ILIKE :q OR " \
          "COALESCE(addresses.cidade, habitations.cidade) ILIKE :q",
          q: query
        )
      end

      if @habitation_status.present?
        scope = scope.where(status: @habitation_status)
      end

      @habitation_status_options = @proprietor.habitations.where.not(status: [nil, ""]).distinct.order(:status).pluck(:status)
      @linked_habitations = scope.paginate(page: params[:habitations_page], per_page: 10)
    end
  end
end
