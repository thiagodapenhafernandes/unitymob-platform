module Admin
  class ProprietorsController < BaseController
    require "csv"
    before_action -> { check_permission!(:view, :proprietarios) }, except: %i[quick_search quick_create quick_update]
    before_action -> { check_permission!(:manage, :proprietarios) }, only: %i[new create edit update destroy]
    before_action :authorize_quick_proprietor_access!, only: %i[quick_search quick_create quick_update]
    before_action :set_quick_proprietor, only: %i[quick_update]

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
      @habitations_count_by_proprietor = current_tenant.habitations.where(proprietor_id: @proprietors.map(&:id)).group(:proprietor_id).count

      @capture_vehicle_options = Proprietor::CAPTURE_VEHICLES
      tenant_proprietors = current_tenant.proprietors
      tenant_habitations = current_tenant.habitations
      @name_options = tenant_proprietors.where.not(name: [nil, ""]).distinct.order(:name).pluck(:name)
      @city_options = tenant_proprietors.distinct_city_suggestions
      @email_options = tenant_proprietors.where.not(email: [nil, ""]).distinct.order(:email).pluck(:email)
      @phone_options = tenant_proprietors
        .pluck(:phone_primary, :mobile_phone, :residential_phone, :business_phone)
        .flatten
        .map { |value| value.to_s.strip }
        .reject(&:blank?)
        .uniq
        .sort
      @spouse_name_options = tenant_proprietors.where.not(spouse_name: [nil, ""]).distinct.order(:spouse_name).pluck(:spouse_name)
      @spouse_email_options = tenant_proprietors.where.not(spouse_email: [nil, ""]).distinct.order(:spouse_email).pluck(:spouse_email)
      @spouse_phone_options = tenant_proprietors.where.not(spouse_phone: [nil, ""]).distinct.order(:spouse_phone).pluck(:spouse_phone)

      reference_codes = tenant_habitations.where.not(codigo: [nil, ""]).distinct.order(:codigo).limit(200).pluck(:codigo)
      reference_titles = tenant_habitations.where.not(titulo_anuncio: [nil, ""]).distinct.order(:titulo_anuncio).limit(200).pluck(:titulo_anuncio)
      reference_developments = tenant_habitations.where.not(nome_empreendimento: [nil, ""]).distinct.order(:nome_empreendimento).limit(200).pluck(:nome_empreendimento)
      @habitation_reference_options = (reference_codes + reference_titles + reference_developments).map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort
      @habitation_address_options = tenant_habitations.where.not(endereco: [nil, ""]).distinct.order(:endereco).limit(400).pluck(:endereco)
      @habitation_number_options = tenant_habitations.where.not(numero: [nil, ""]).distinct.order(:numero).limit(300).pluck(:numero)

      @habitation_category_options = tenant_habitations.where.not(categoria: [nil, ""]).distinct.order(:categoria).pluck(:categoria)
      @habitation_status_options = tenant_habitations.where.not(status: [nil, ""]).distinct.order(:status).pluck(:status)
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
      proprietors = apply_index_filters(current_tenant.proprietors.left_outer_joins(:habitations), filters).distinct.order(name: :asc)
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
      @proprietor = current_tenant.proprietors.new
    end

    def edit
      load_habitations
    end

    def create
      @proprietor = current_tenant.proprietors.new(proprietor_params)

      if @proprietor.save
        redirect_to admin_proprietors_path, notice: "Proprietário criado com sucesso."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def quick_search
      query = params[:q].to_s.strip
      proprietors =
        if query.present?
          digits = query.gsub(/\D/, "")
          scope = current_tenant.proprietors
          text_matches = quick_search_text_scope(scope, query)

          matches =
            if digits.present?
              phone_matches = quick_search_phone_scope(scope, query)
              text_matches.or(phone_matches)
            else
              text_matches
            end

          matches.distinct.order(:name).limit(12)
        else
          current_tenant.proprietors.none
        end

      render json: {
        proprietors: proprietors.map { |proprietor| quick_proprietor_payload(proprietor) }
      }
    end

    def quick_create
      permitted = quick_proprietor_params
      missing = []
      missing << "Nome é obrigatório." if permitted[:name].blank?
      missing << "Telefone é obrigatório." if permitted[:phone_primary].blank?
      missing << "Cidade é obrigatória." if permitted[:city].blank?
      missing << quick_phone_error(permitted[:phone_primary]) if permitted[:phone_primary].present?
      missing.compact!
      return render json: { errors: missing }, status: :unprocessable_entity if missing.any?

      phone = permitted[:phone_primary].presence
      phone_digits = Proprietor.normalized_phone(phone)
      if phone_digits.present?
        @proprietor = current_tenant.proprietors.with_normalized_phone(phone_digits).order(:id).first
        if @proprietor.present?
          render json: {
            duplicate: true,
            errors: [duplicate_quick_proprietor_message(@proprietor)],
            proprietor: quick_proprietor_payload(@proprietor)
          }, status: :conflict
          return
        end
      end

      @proprietor = current_tenant.proprietors.new(role: :owner)
      quick_proprietor_params.to_h.compact_blank.each do |attribute, value|
        @proprietor.public_send("#{attribute}=", value)
      end

      if @proprietor.save
        render json: quick_proprietor_payload(@proprietor), status: :created
      else
        render json: { errors: @proprietor.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def quick_update
      attributes = quick_update_attributes
      phone_error = quick_phone_error(attributes[:phone_primary]) if attributes[:phone_primary].present?
      return render json: { errors: [phone_error] }, status: :unprocessable_entity if phone_error.present?

      if (duplicate = duplicate_quick_proprietor_for(attributes))
        render json: {
          duplicate: true,
          errors: [duplicate_quick_proprietor_message(duplicate)],
          proprietor: quick_proprietor_payload(duplicate)
        }, status: :conflict
      elsif @proprietor.update(attributes)
        render json: quick_proprietor_payload(@proprietor)
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
      @proprietor = current_tenant.proprietors.find_by(id: params[:id])
      return if @proprietor.present?

      # Compatibilidade com links legados do módulo de construtoras.
      legacy_constructor = Constructor.find_by(id: params[:id]) if defined?(Constructor)
      if legacy_constructor.present?
        @proprietor = current_tenant.proprietors.find_or_create_by!(name: legacy_constructor.name) do |p|
          p.role = :builder
        end
        redirect_to edit_admin_proprietor_path(@proprietor), notice: "Cadastro legado convertido para Proprietário."
        return
      end

      redirect_to admin_proprietors_path, alert: "Proprietário não encontrado."
    end

    def set_quick_proprietor
      @proprietor = current_tenant.proprietors.find_by(id: params[:id])
      render json: { errors: ["Proprietário não encontrado."] }, status: :not_found unless @proprietor
    end

    def authorize_quick_proprietor_access!
      return if admin_or_administrative_user? || can?(:manage, :captacoes)
      return if quick_property_owner_permission?

      render json: { errors: ["Acesso restrito a usuários com permissão para gerenciar proprietários no cadastro do imóvel."] }, status: :forbidden
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
        :city
      )
    end

    def quick_update_attributes
      permitted = quick_proprietor_params.to_h.symbolize_keys
      permitted.delete_if { |attribute, value| value.blank? && attribute != :email }
      return permitted if admin_or_administrative_user? || quick_property_owner_permission?

      attributes = permitted.slice(:email, :city)
      attributes[:phone_primary] = permitted[:phone_primary] if permitted[:phone_primary].present? && quick_proprietor_phone_blank?(@proprietor)
      attributes
    end

    def quick_property_owner_permission?
      return false unless can?(:edit, :imoveis)

      policy = Habitations::FieldLockPolicy.for(current_admin_user)
      return false if policy.field_locked?("proprietor_id")
      return true unless action_name == "quick_create"

      !policy.action_locked?("acao:cadastrar_proprietario")
    end

    def quick_search_text_scope(scope, query)
      terms = query.split(/\s+/).filter_map do |word|
        sanitized = ActiveRecord::Base.sanitize_sql_like(word.to_s.strip)
        sanitized if sanitized.length >= 2
      end

      terms = [ActiveRecord::Base.sanitize_sql_like(query)] if terms.blank?

      predicates = []
      bindings = {}
      terms.each_with_index do |term, index|
        key = :"term_#{index}"
        predicates << "proprietors.name ILIKE :#{key} OR proprietors.email ILIKE :#{key} OR proprietors.city ILIKE :#{key}"
        bindings[key] = "%#{term}%"
      end

      scope.where(predicates.map { |predicate| "(#{predicate})" }.join(" OR "), bindings)
    end

    def quick_search_phone_scope(scope, query)
      digits = query.to_s.gsub(/\D/, "")
      candidates = quick_phone_search_candidates(query)
      predicates = [
        "regexp_replace(COALESCE(proprietors.phone_primary, ''), '\\D', '', 'g') LIKE :raw_digits",
        "regexp_replace(COALESCE(proprietors.mobile_phone, ''), '\\D', '', 'g') LIKE :raw_digits",
        "regexp_replace(COALESCE(proprietors.residential_phone, ''), '\\D', '', 'g') LIKE :raw_digits",
        "regexp_replace(COALESCE(proprietors.business_phone, ''), '\\D', '', 'g') LIKE :raw_digits"
      ]
      bindings = { raw_digits: "%#{digits}%" }

      if candidates.any?
        predicates.concat([
          "regexp_replace(COALESCE(proprietors.phone_primary, ''), '\\D', '', 'g') IN (:phone_candidates)",
          "regexp_replace(COALESCE(proprietors.mobile_phone, ''), '\\D', '', 'g') IN (:phone_candidates)",
          "regexp_replace(COALESCE(proprietors.residential_phone, ''), '\\D', '', 'g') IN (:phone_candidates)",
          "regexp_replace(COALESCE(proprietors.business_phone, ''), '\\D', '', 'g') IN (:phone_candidates)"
        ])
        bindings[:phone_candidates] = candidates
      end

      scope.where(predicates.map { |predicate| "(#{predicate})" }.join(" OR "), bindings)
    end

    def quick_phone_search_candidates(query)
      digits = query.to_s.gsub(/\D/, "")
      normalized = Proprietor.normalized_phone(query)
      [digits, normalized].compact_blank.uniq.select { |candidate| candidate.length >= 8 }
    end

    def quick_phone_error(value)
      raw_value = value.to_s.strip
      digits = raw_value.gsub(/\D/, "")
      normalized = Proprietor.normalized_phone(raw_value)

      return "Telefone inválido. Informe um telefone válido com DDD." if normalized.blank?
      return "Telefone inválido. Informe um telefone com DDD ou selecione o país correto." if digits.blank?

      if raw_value.start_with?("+") && !digits.start_with?(Phones::Normalizer::BRAZIL_COUNTRY_CODE)
        return if normalized.length.between?(Phones::Normalizer::MIN_E164_LENGTH, Phones::Normalizer::MAX_E164_LENGTH)

        return "Telefone inválido. Números internacionais devem ter entre 8 e 15 dígitos."
      end

      national_digits = quick_brazilian_national_digits(digits)
      return if national_digits.length == 11 && national_digits[2] == "9"

      "Telefone inválido para WhatsApp no Brasil. Informe DDD + número com 9 dígitos, exemplo: (47) 98851-6745."
    end

    def quick_brazilian_national_digits(digits)
      return digits.delete_prefix(Phones::Normalizer::BRAZIL_COUNTRY_CODE) if digits.start_with?(Phones::Normalizer::BRAZIL_COUNTRY_CODE)

      digits
    end

    def duplicate_quick_proprietor_message(proprietor)
      "Já existe um proprietário cadastrado com este telefone: #{proprietor.name}. Pesquise pelo telefone informado e selecione o cadastro existente."
    end

    def quick_proprietor_phone_blank?(proprietor)
      [
        proprietor.phone_primary,
        proprietor.mobile_phone,
        proprietor.residential_phone,
        proprietor.business_phone
      ].compact_blank.empty?
    end

    def duplicate_quick_proprietor_for(attributes)
      phone_digits = Proprietor.normalized_phone(attributes[:phone_primary])
      return if phone_digits.blank?

      current_tenant.proprietors
                    .with_normalized_phone(phone_digits)
                    .where.not(id: @proprietor.id)
                    .order(:id)
                    .first
    end

    def quick_proprietor_payload(proprietor)
      phones = [
        proprietor.phone_primary,
        proprietor.mobile_phone,
        proprietor.business_phone,
        proprietor.residential_phone
      ].compact_blank.uniq

      {
        id: proprietor.id,
        name: proprietor.name,
        label: proprietor.select_label,
        phone_primary: phones.first,
        phone_primary_display: Phones::Normalizer.display(phones.first),
        phone_secondary: phones.second,
        phone_secondary_display: Phones::Normalizer.display(phones.second),
        email: proprietor.email,
        city: proprietor.city,
        edit_path: edit_admin_proprietor_path(proprietor)
      }
    end

    def proprietor_filter_params
      params.fetch(:filters, {}).permit(
        :name, :phone, :email, :city
      )
    end

    def filtered_proprietors_scope
      apply_index_filters(current_tenant.proprietors.left_outer_joins(:habitations), @filters)
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
        phone_digits = filters[:phone].to_s.gsub(/\D/, "")
        if phone_digits.length >= 8
          normalized_phone = Proprietor.normalized_phone(filters[:phone])
          scope = scope.with_normalized_phone(normalized_phone)
        elsif phone_digits.present?
          scope = scope.where(
            "regexp_replace(COALESCE(proprietors.phone_primary, ''), '\\D', '', 'g') LIKE :q OR " \
            "regexp_replace(COALESCE(proprietors.mobile_phone, ''), '\\D', '', 'g') LIKE :q OR " \
            "regexp_replace(COALESCE(proprietors.residential_phone, ''), '\\D', '', 'g') LIKE :q OR " \
            "regexp_replace(COALESCE(proprietors.business_phone, ''), '\\D', '', 'g') LIKE :q",
            q: "%#{phone_digits}%"
          )
        end
      end

      if filters[:cpf_cnpj].present?
        # CPF cifrado: busca é por documento COMPLETO (igualdade nos dígitos).
        if Proprietor.cpf_digits_searchable?
          scope = scope.where(cpf_cnpj_digits: Proprietor.normalized_cpf_cnpj(filters[:cpf_cnpj]))
        else
          scope = scope.where("proprietors.cpf_cnpj ILIKE ?", like(filters[:cpf_cnpj]))
        end
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
        if Proprietor.cpf_digits_searchable?
          scope = scope.where(spouse_cpf_cnpj_digits: Proprietor.normalized_cpf_cnpj(filters[:spouse_cpf_cnpj]))
        else
          scope = scope.where("proprietors.spouse_cpf_cnpj ILIKE ?", like(filters[:spouse_cpf_cnpj]))
        end
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
