module Admin
  class HabitationIntakesController < Admin::BaseController
    include RentalGuaranteeParamNormalizer

    before_action -> { check_permission!(:view, :captacoes) }
    before_action -> { check_permission!(:manage, :captacoes) }, only: %i[new create edit update destroy submit_for_review release_to_site publish proprietor_lookup]
    before_action :authorize_export!, only: %i[export]
    before_action :set_property_setting, only: %i[show edit update destroy submit_for_review approve return_to_broker release_to_site publish]
    before_action :set_habitation, only: %i[show edit update destroy submit_for_review approve return_to_broker release_to_site]
    before_action :authorize_access!, only: %i[show edit update destroy submit_for_review release_to_site]
    before_action :authorize_intake_edit!, only: %i[edit update]
    before_action :authorize_review!, only: %i[approve return_to_broker]
    before_action :load_form_options, only: %i[edit update]
    layout :resolve_layout
    helper_method :can_export_captacoes?, :can_broker_release_to_site?, :can_filter_intakes_by_broker?

    def index
      @status = params[:status].presence
      @q = params[:q].to_s.strip
      build_index_dashboard
      @habitations = filtered_intakes_scope.includes(:admin_user, :admin_reviewed_by, :address)
      @habitations = @habitations.order(updated_at: :desc).paginate(page: params[:page], per_page: 20)
      @captacoes = @habitations
      @captacao_brokers = captacao_broker_options
      render "admin/captacoes/index"
    end

    def export
      scope = filtered_intakes_scope.includes(:admin_user, :address).order(created_at: :asc)
      csv_content = Captacoes::SpreadsheetExporter.new(scope, helpers: helpers).to_csv
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "captacoes_#{timestamp}.csv"

      record_data_export!(
        record_count: scope.count,
        filename: filename,
        filters: export_filters
      )

      send_data csv_content,
                filename: filename,
                type: "text/csv; charset=utf-8"
    end

    def new
      @captacao = build_intake_preview
      render "admin/captacoes/new"
    end

    def create
      start_new_intake
    end

    def proprietor_lookup
      match = matching_proprietor_for_lookup

      if match.present?
        proprietor, matched_by = match
        render json: {
          found: true,
          matched_by: matched_by,
          proprietor: proprietor_lookup_payload(proprietor)
        }
      else
        render json: { found: false }
      end
    end

    def show
      @captacao = @habitation
      @review_timeline = HabitationReviewTimeline.new(habitation: @habitation).call
      render "admin/captacoes/show"
    end

    def edit
      @captacao = @habitation
      @step = params[:step].presence_in(Captacao::STEPS) || @habitation.intake_step.presence || "intro"
      @step = @captacao.next_step if @step == "visitas" && @captacao.skip_visitas?
      render "admin/captacoes/edit"
    end

    def update
      @captacao = @habitation
      current_step = params[:current_step].presence_in(Captacao::STEPS) || @habitation.intake_step.presence || "intro"
      direction = params[:direction].to_s

      if direction == "back"
        target = @habitation.previous_step || current_step
        @habitation.assign_attributes(captacao_style_params) if intake_param_key.present?
        @habitation.update_column(:intake_step, target)
        redirect_to edit_admin_captacao_path(@habitation, step: target)
        return
      end

      if published_restricted_update?
        @habitation.assign_attributes(published_restricted_params)
      else
        @habitation.assign_attributes(captacao_style_params)
      end
      touch_manual_habitation_update!(@habitation)

      if duplicate_address_blocks_intake?(current_step)
        assign_duplicate_address_errors
        @step = current_step
        render "admin/captacoes/edit", status: :unprocessable_entity
        return
      end

      if @habitation.save
        apply_intake_photo_ambientes!(@habitation)
        enqueue_photo_calendar_sync_if_needed!(@habitation)
        unless step_requirements_met?(current_step)
          assign_step_errors(current_step)
          @step = current_step
          @habitation.update_column(:intake_step, current_step) if @habitation.persisted?
          render "admin/captacoes/edit", status: :unprocessable_entity
          return
        end

        if current_step == "review"
          required_checks = active_broker_capture_checks
          missing_requirements = @habitation.intake_missing_requirements(
            required_checks: required_checks,
            require_owner_city: true
          )
          if missing_requirements.present?
            missing_requirements.each { |message| @habitation.errors.add(:base, message) }
            @step = current_step
            render "admin/captacoes/edit", status: :unprocessable_entity
            return
          end

          submitted_records = HabitationIntakeSplitter.new(
            @habitation,
            target_intake_status: target_broker_capture_status
          ).call!
          redirect_to admin_captacao_path(@habitation),
                      notice: submission_notice(submitted_records, target_broker_capture_status)
        else
          next_step = @habitation.next_step
          next_step = @habitation.next_step if next_step == "visitas" && @habitation.skip_visitas?
          @habitation.update_column(:intake_step, next_step)
          redirect_to edit_admin_captacao_path(@habitation, step: next_step)
        end
      else
        @step = current_step
        render "admin/captacoes/edit", status: :unprocessable_entity
      end
    end

    def destroy
      if @habitation.intake_published?
        redirect_to admin_captacoes_path, alert: "Captações já liberadas para site não podem ser removidas por aqui."
      else
        @habitation.destroy
        redirect_to admin_captacoes_path, notice: "Captação removida."
      end
    end

    def touch_manual_habitation_update!(habitation)
      habitation.data_atualizacao_crm = Time.current if habitation.changed?
    end

    def link_proprietor_from_intake_fields
      Habitations::ProprietorLinker.new(@habitation).call
    end

    def submit_for_review
      @habitation.assign_attributes(captacao_style_params) if intake_param_key.present?
      link_proprietor_from_intake_fields
      touch_manual_habitation_update!(@habitation)

      if duplicate_address_blocks_intake?("review")
        load_form_options
        assign_duplicate_address_errors
        flash.now[:alert] = "Complete os campos obrigatórios antes de enviar."
        @captacao = @habitation
        @step = "review"
        render "admin/captacoes/edit", status: :unprocessable_entity
        return
      end

      required_checks = active_broker_capture_checks
      if @habitation.intake_ready_for_admin_review?(required_checks: required_checks, require_owner_city: true) && @habitation.save
        submitted_records = HabitationIntakeSplitter.new(
          @habitation,
          target_intake_status: target_broker_capture_status
        ).call!
        notify_review_events(submitted_records, event: "submit_for_review")
        redirect_to admin_captacao_path(@habitation),
                    notice: submission_notice(submitted_records, target_broker_capture_status)
      else
        load_form_options
        @missing_requirements = @habitation.intake_missing_requirements(
          required_checks: required_checks,
          require_owner_city: true
        )
        flash.now[:alert] = "Complete os campos obrigatórios antes de enviar."
        @captacao = @habitation
        @step = "review"
        render "admin/captacoes/edit", status: :unprocessable_entity
      end
    end

    def approve
      link_proprietor_from_intake_fields

      unless @habitation.intake_status.in?(%w[submitted_for_admin_review admin_approved])
        redirect_to admin_captacao_path(@habitation),
                    alert: "Esta captação não está em fase de revisão administrativa."
        return
      end

      required_checks = active_broker_capture_checks
      unless @habitation.intake_ready_for_admin_review?(required_checks: required_checks, require_owner_city: true)
        missing = @habitation.intake_missing_requirements(
          required_checks: required_checks,
          require_owner_city: true
        ).to_sentence
        redirect_to admin_captacao_path(@habitation),
                    alert: "Complete os campos obrigatórios antes de aprovar: #{missing}."
        return
      end

      @habitation.update!(
        intake_status: "admin_approved",
        admin_reviewed_by: current_admin_user,
        admin_reviewed_at: Time.current,
        admin_review_notes: admin_review_notes
      )
      notify_review_events([@habitation], event: "approve", notes: admin_review_notes)
      redirect_to admin_captacao_path(@habitation), notice: "Captação liberada pelo administrativo."
    end

    def return_to_broker
      unless @habitation.intake_status.in?(%w[submitted_for_admin_review admin_approved])
        redirect_to admin_captacao_path(@habitation),
                    alert: "Esta captação não pode ser devolvida nesta etapa."
        return
      end

      if admin_review_return_reason.blank? || admin_review_notes.blank?
        redirect_to admin_captacao_path(@habitation),
                    alert: "Informe o motivo da devolução e a nota interna para devolver ao corretor."
        return
      end

      @habitation.update!(
        intake_status: "returned_to_broker",
        admin_reviewed_by: current_admin_user,
        admin_reviewed_at: Time.current,
        admin_review_notes: admin_review_notes,
        admin_review_return_reason: admin_review_return_reason
      )
      notify_review_events([@habitation], event: "return_to_broker", notes: admin_review_notes, return_reason: admin_review_return_reason)
      redirect_to admin_captacao_path(@habitation), notice: "Captação devolvida ao corretor."
    end

    def release_to_site
      unless can_broker_release_to_site?(@habitation)
        redirect_to admin_captacao_path(@habitation), alert: "Apenas o captador responsável pode publicar no site."
        return
      end

      unless @habitation.broker_can_release_to_site?(required_checks: active_broker_capture_checks)
        missing = @habitation.intake_missing_requirements(
          required_checks: active_broker_capture_checks,
          require_owner_city: true
        ).to_sentence
        alert = "Esta captação ainda não está pronta para liberar no site."
        alert = "#{alert} Pendências: #{missing}." if missing.present?
        redirect_to admin_captacao_path(@habitation), alert: alert
        return
      end

      @habitation.update!(
        intake_status: "published",
        broker_released_at: Time.current,
        data_atualizacao_crm: Time.current,
        exibir_no_site_flag: true,
        foto_classificacao: @habitation.foto_classificacao.presence || "Boas"
      )
      notify_review_events([@habitation], event: "release_to_site")
      redirect_to admin_captacao_path(@habitation), notice: "Imóvel liberado para o site."
    end

    def publish
      if @habitation.intake_admin_approved?
        release_to_site
      elsif can?(:review, :captacoes)
        approve
      else
        redirect_to admin_captacao_path(@habitation), alert: "Captação ainda precisa de aprovação administrativa."
      end
    end

    private

    def matching_proprietor_for_lookup
      scope = current_tenant.proprietors

      code = params[:code].to_s.strip
      if code.present?
        proprietor = scope.where("trim(vista_code) = ?", code).order(:id).first
        return [proprietor, "code"] if proprietor
      end

      phone_digits = Proprietor.normalized_phone(params[:phone])
      if phone_digits.length >= 8
        proprietor = scope.with_normalized_phone(phone_digits).order(:id).first
        return [proprietor, "phone"] if proprietor
      end

      cpf_digits = Proprietor.normalized_cpf_cnpj(params[:cpf_cnpj])
      if cpf_digits.length.in?([11, 14])
        proprietor =
          if Proprietor.cpf_digits_searchable?
            scope.where(cpf_cnpj_digits: cpf_digits).order(:id).first
          else
            scope.where("regexp_replace(COALESCE(cpf_cnpj, ''), '\\D', '', 'g') = :digits", digits: cpf_digits).order(:id).first
          end
        return [proprietor, "cpf_cnpj"] if proprietor
      end

      email = params[:email].to_s.strip.downcase
      if email.match?(URI::MailTo::EMAIL_REGEXP)
        proprietor = scope.where("lower(trim(email)) = ?", email).order(:id).first
        return [proprietor, "email"] if proprietor
      end

      nil
    end

    def proprietor_lookup_payload(proprietor)
      {
        id: proprietor.id,
        code: proprietor.vista_code,
        name: proprietor.name,
        phone: proprietor.mobile_phone.presence || proprietor.phone_primary.presence || proprietor.residential_phone.presence || proprietor.business_phone.presence,
        cpf_cnpj: proprietor.cpf_cnpj,
        email: proprietor.email,
        city: proprietor.city,
        label: proprietor.select_label
      }
    end

    # Persiste o ambiente por foto submetido no cadastro (params habitation/captacao
    # [photo_ambientes][<attachment_id>] => ambiente). Mesmo gate do editor: só quem
    # pode gerenciar imóveis (corretor não). Best-effort: nunca derruba o save.
    def apply_intake_photo_ambientes!(record)
      return unless current_admin_user&.can?(:manage, :imoveis)
      return unless record.respond_to?(:set_photo_ambiente!)

      raw = params.dig(:habitation, :photo_ambientes) || params.dig(:captacao, :photo_ambientes)
      return if raw.blank?

      attachments = record.respond_to?(:photos) ? record.photos : record.fotos
      by_id = attachments.index_by(&:id)
      raw.to_unsafe_h.each do |photo_id, ambiente|
        value = ambiente.to_s.strip
        next unless value.blank? || Habitation::FOTO_AMBIENTES.include?(value)

        attachment = by_id[photo_id.to_i]
        record.set_photo_ambiente!(attachment, value) if attachment
      end
    rescue StandardError => e
      Rails.logger.warn("[intake] aplicar ambientes das fotos falhou: #{e.message}")
    end

    def enqueue_photo_calendar_sync_if_needed!(record)
      return unless record.photo_flow_choice.in?(%w[schedule google_calendar])
      return if record.photo_session_requested_at.blank?

      setting = GoogleCalendarIntegrationSetting.for(current_tenant)
      return unless setting.configured?

      GoogleCalendar::PhotoEventSyncJob.perform_later(record.id, tenant_id: current_tenant.id)
    rescue StandardError => e
      Rails.logger.warn("[intake] enfileirar agenda Google falhou para imóvel #{record.id}: #{e.class}: #{e.message}")
    end

    def start_new_intake
      habitation = build_intake_preview
      habitation.intake_step = "proprietario"

      habitation.save!
      redirect_to edit_admin_captacao_path(habitation, step: "proprietario"), notice: "Captação iniciada."
    end

    def build_intake_preview
      current_tenant.habitations.new(
        admin_user: current_admin_user,
        intake_origin: Habitation::INTAKE_ORIGIN_BROKER,
        intake_status: "draft",
        exibir_no_site_flag: false,
        categoria: "Apartamento",
        status: default_status,
        tipo: "Unitário",
        foto_classificacao: "Não tem fotos",
        intake_modalidade: default_modalidade
      ).tap do |habitation|
        habitation.assign_attributes(initial_intake_params) if params[:habitation].present?
      end
    end

    def initial_intake_params
      attrs = params.require(:habitation).permit(:cadastro_type, :property_kind, :categoria, :modalidade).compact_blank.to_h
      cadastro_type = attrs.delete("cadastro_type")
      property_kind = attrs.delete("property_kind")
      default_category = default_category_for_cadastro_type(cadastro_type.presence || property_kind)
      attrs["categoria"] = default_category if attrs["categoria"].blank? && default_category.present?
      attrs
    end

    def admin_review_return_reason
      params[:admin_review_return_reason].to_s.strip.presence
    end

    def admin_review_notes
      params[:admin_review_notes].to_s.strip.presence
    end

    def set_habitation
      @habitation = current_tenant.habitations.broker_intakes.friendly.find(params[:id])
    end

    def set_property_setting
      @property_setting = PropertySetting.instance
    end

    def target_broker_capture_status
      return "admin_approved" unless @property_setting&.broker_capture_layer_enabled

      "submitted_for_admin_review"
    end

    def active_broker_capture_checks
      @property_setting&.active_broker_capture_checks
    end

    def intake_check_enabled?(key)
      @active_broker_capture_check_set ||= PropertySetting.normalize_intake_checks(active_broker_capture_checks)
      @active_broker_capture_check_set.include?(key.to_s)
    end

    def authorize_export!
      return if can_export_captacoes?

      redirect_to admin_captacoes_path, alert: "Você não tem permissão para exportar captações."
    end

    def can_export_captacoes?
      tenant_owner? || owns_all_resource?(:captacoes) || can?(:review, :captacoes)
    end

    def can_broker_release_to_site?(habitation)
      return false unless habitation&.broker_release_pending?
      return false if tenant_owner? || can?(:review, :captacoes)

      habitation.broker_responsible_for?(current_admin_user)
    end

    def scoped_intakes
      scope = current_tenant.habitations.broker_intakes
      if owns_all_resource?(:captacoes) || can?(:review, :captacoes)
        return scope.where(
          "(habitations.intake_status IS NOT NULL AND habitations.intake_status NOT IN (:draft_statuses)) OR habitations.admin_user_id = :user_id",
          draft_statuses: ["draft"],
          user_id: current_admin_user.id
        )
      end

      scope.where(admin_user_id: visible_owner_ids(:captacoes) || [current_admin_user.id])
    end

    def can_filter_intakes_by_broker?
      tenant_owner? || can?(:review, :captacoes) || owns_all_resource?(:captacoes)
    end

    def captacao_broker_options
      return AdminUser.none unless can_filter_intakes_by_broker?

      current_tenant.admin_users.where(id: scoped_intakes.reorder(nil).distinct.select(:admin_user_id)).order(:name)
    end

    def filtered_intakes_scope
      scope = scoped_intakes
      scope = scope.where(categoria: "Terreno") if params[:property_kind] == "terreno"
      scope = scope.where(categoria: "Sala Comercial") if params[:property_kind] == "sala_comercial"
      scope = scope.where.not(categoria: ["Terreno", "Sala Comercial"]) if params[:property_kind] == "residencial"

      case params[:status].presence
      when "draft"
        scope = scope.where(intake_status: [nil, "draft", "returned_to_broker"])
      when "completed"
        scope = scope.where(intake_status: %w[submitted_for_admin_review admin_approved])
      when "published"
        scope = scope.where(intake_status: "published")
      when nil, ""
        scope = scope.where.not(intake_status: %w[internal published])
      else
        scope = scope.where(intake_status: params[:status]) if params[:status].present?
      end

      if params[:corretor_id].present? && can_filter_intakes_by_broker?
        scope = scope.where(admin_user_id: params[:corretor_id])
      end

      q = params[:q].to_s.strip
      if q.present?
        scope = scope.where(
          "codigo ILIKE :q OR titulo_anuncio ILIKE :q OR nome_empreendimento ILIKE :q OR proprietario ILIKE :q",
          q: "%#{q}%"
        )
      end

      scope
    end

    def build_index_dashboard
      scope = scoped_intakes
      status_counts = scope.group(:intake_status).count
      modality_counts = scope.group(:intake_modalidade).count
      total = scope.count
      commercial_count = scope.where(
        "categoria ILIKE :sala OR categoria ILIKE :loja OR categoria ILIKE :comercial",
        sala: "%Sala%",
        loja: "%Loja%",
        comercial: "%Comercial%"
      ).count
      land_count = scope.where("categoria ILIKE ?", "%Terreno%").count

      @captacoes_dashboard = {
        total: total,
        draft: status_counts[nil].to_i + status_counts["draft"].to_i,
        returned_to_broker: status_counts["returned_to_broker"].to_i,
        submitted_for_admin_review: status_counts["submitted_for_admin_review"].to_i,
        admin_approved: status_counts["admin_approved"].to_i,
        published: status_counts["published"].to_i,
        last_7_days: scope.where(created_at: 7.days.ago.beginning_of_day..Time.current).count,
        missing_photos: missing_photos_count(scope),
        property_kinds: {
          residencial: [total - commercial_count - land_count, 0].max,
          sala_comercial: commercial_count,
          terreno: land_count
        },
        modalities: {
          venda: modality_counts["venda"].to_i,
          locacao_anual: modality_counts["locacao_anual"].to_i,
          ambos: modality_counts["ambos"].to_i,
          locacao_diaria: modality_counts["locacao_diaria"].to_i,
          blank: modality_counts[nil].to_i
        }
      }
    end

    def missing_photos_count(scope)
      scope
        .where("pictures IS NULL OR pictures = '[]'::jsonb")
        .where(<<~SQL.squish)
          NOT EXISTS (
            SELECT 1
            FROM active_storage_attachments
            WHERE active_storage_attachments.record_type = 'Habitation'
              AND active_storage_attachments.record_id = habitations.id
              AND active_storage_attachments.name = 'photos'
          )
        SQL
        .count
    end

    def export_filters
      params.to_unsafe_h.slice("property_kind", "status", "q")
    end

    def record_data_export!(record_count:, filename:, filters:)
      Audit::DataExportRecorder.call(
        admin_user: current_admin_user,
        request: request,
        export_type: "csv_export",
        resource_name: "captacoes",
        format: "csv_semicolon",
        record_count: record_count,
        selected_count: 0,
        filename: filename,
        filters: filters,
        fields: Captacoes::SpreadsheetExporter::HEADERS
      )
    end

    def authorize_access!
      return if owns_all_resource?(:captacoes) || can?(:review, :captacoes)
      return if @habitation.admin_user_id == current_admin_user.id

      redirect_to admin_captacoes_path, alert: "Você não tem acesso a esta captação."
    end

    def authorize_intake_edit!
      return unless @habitation.intake_submitted_for_admin_review?
      return if can?(:review, :captacoes)
      return if current_admin_user&.can_view_team?(:captacoes) && manager_can_access_intake?(@habitation)

      redirect_to admin_captacoes_path, alert: "Captações pendentes de revisão só podem ser alteradas por quem revisa captações ou pelo gestor responsável."
    end

    def manager_team_user_ids
      return [] unless current_admin_user

      ids = current_admin_user.team_scope_ids
      return ids if current_admin_user.both?

      current_tenant.admin_users.where(id: ids, acting_type: manager_allowed_acting_types).pluck(:id)
    end

    def manager_allowed_acting_types
      case current_admin_user&.acting_type
      when "sales" then AdminUser.acting_types.values_at("sales", "both")
      when "rentals" then AdminUser.acting_types.values_at("rentals", "both")
      else AdminUser.acting_types.values
      end
    end

    def manager_can_access_intake?(habitation)
      manager_team_user_ids.include?(habitation.admin_user_id)
    end

    def authorize_review!
      return if can?(:review, :captacoes)

      redirect_to admin_captacoes_path, alert: "Você não tem permissão para aprovar captações."
    end

    def default_status
      current_admin_user&.rentals? ? "Aluguel" : "Venda"
    end

    def default_modalidade
      case current_admin_user&.acting_type
      when "rentals" then "locacao_anual"
      when "sales" then "venda"
      else "venda"
      end
    end

    def load_form_options
      @brokers = current_tenant.admin_users.account_members.order(:name)
      @proprietors = current_tenant.proprietors.order(:name).limit(300)
      @developments = current_tenant.habitations.empreendimentos
        .includes(:address)
        .select(
          :id, :slug, :codigo, :nome_empreendimento, :titulo_anuncio,
          :constructor_id, :proprietor_id, :admin_user_id, :data_entrega,
          :perfil_construcao, :tipo_endereco, :endereco, :numero,
          :bairro, :bairro_comercial, :cidade, :uf, :cep
        )
        .where("NULLIF(TRIM(nome_empreendimento), '') IS NOT NULL AND nome_empreendimento != '.'")
        .order(nome_empreendimento: :asc)
      @proprietor_city_options = current_tenant.proprietors
        .where.not(city: [nil, ""])
        .distinct
        .order(:city)
        .limit(100)
        .pluck(:city)
        .map { |city| city.to_s.strip }
        .compact_blank
      @internal_features = (
        current_tenant.attribute_options.where(context: "habitation", category: "feature").order(:name).pluck(:name) +
        Admin::HabitationsController::CUSTOM_FEATURE_OPTIONS
      ).uniq.sort
      @external_features = current_tenant.attribute_options.where(context: "habitation", category: "infrastructure").order(:name).pluck(:name)
      @badges = current_tenant.attribute_options.where(context: "habitation", category: "unique_feature").order(:name).pluck(:name)
      @sale_reasons = sale_reason_options
      @google_calendar_setting = GoogleCalendarIntegrationSetting.for(current_tenant)
      @google_calendar_configured = @google_calendar_setting.configured?
      @photography_min_date = Date.current + 1.day
      @photography_blocked_dates = PhotographyScheduleBlock.pluck(:date).map(&:iso8601)
      @photography_booked_slots = booked_photography_slots
    end

    def booked_photography_slots
      local_booked_slots = current_tenant.habitations
        .broker_intakes
        .where(photo_flow_choice: %w[schedule google_calendar])
        .where.not(id: @habitation&.id)
        .where.not(photo_session_requested_at: nil)
        .pluck(:photo_session_requested_at)
        .map { |date| date.strftime("%Y-%m-%dT%H:%M") }

      (local_booked_slots + google_calendar_booked_slots).uniq.sort
    end

    def google_calendar_booked_slots
      return [] unless @google_calendar_setting&.configured?

      GoogleCalendar::AvailabilityReader.new(
        setting: @google_calendar_setting,
        tenant: current_tenant,
        start_date: @photography_min_date,
        days: 30
      ).busy_slot_values
    rescue StandardError => e
      Rails.logger.warn("[intake] consultar disponibilidade Google Calendar falhou: #{e.class}: #{e.message}")
      []
    end

    def resolve_layout
      action_name.in?(%w[new create edit update]) ? "captacao_wizard" : "admin"
    end

    def step_requirements_met?(step)
      step_missing_requirements(step).empty?
    end

    def assign_step_errors(step)
      @step_errors = step_missing_requirements(step)
      @invalid_fields = invalid_fields_for_step(step)
      @step_errors.each { |message| @habitation.errors.add(:base, message) }
    end

    def step_missing_requirements(step)
      case step
      when "proprietario"
        missing = []
        missing << "Informe o nome do proprietário." if @habitation.proprietario.blank?
        missing << "Informe o telefone/WhatsApp do proprietário." if @habitation.proprietario_celular.blank?
        missing << "Informe a cidade do proprietário." if intake_check_enabled?(:proprietario_cidade) && @habitation.proprietario_cidade.blank?
        missing
      when "endereco"
        missing = []
        missing << "Informe o CEP." if @habitation.cep.blank?
        missing << "Informe a rua/avenida." if @habitation.logradouro.blank?
        missing << "Informe o número." if @habitation.numero.blank?
        missing << "Informe o bairro." if @habitation.bairro.blank?
        missing << "Informe a cidade." if @habitation.cidade.blank?
        missing << "Informe a UF." if @habitation.uf.blank?
        missing << "Informe o empreendimento/condomínio." if intake_check_enabled?(:empreendimento) && @habitation.requires_intake_development_name? && @habitation.nome_empreendimento.blank?
        missing << "Informe o número da unidade." if intake_check_enabled?(:unidade) && @habitation.requires_unit_number? && @habitation.bloco.blank?
        missing << "Informe o complemento." if @habitation.requires_intake_address_complement? && !@habitation.requires_unit_number? && @habitation.complemento.blank?
        missing
      when "caracteristicas"
        missing = []
        if @habitation.property_kind_terreno? && !@habitation.has_required_intake_area?
          missing << "Informe a área total do imóvel."
        elsif !@habitation.has_required_intake_area?
          missing << "Informe a área privativa do imóvel."
        end
        if @habitation.property_kind_residencial? && @habitation.dormitorios_qtd.to_i <= 0
          missing << "Informe a quantidade de dormitórios."
        end
        if @habitation.property_kind_residencial? && @habitation.banheiros_qtd.to_i <= 0
          missing << "Informe a quantidade de banheiros."
        end
        if @habitation.requires_parking_info?
          missing << "Informe o tipo de vaga." if intake_check_enabled?(:tipo_vaga) && @habitation.tipo_vaga.blank?
          missing << "Informe a quantidade de vagas de garagem." if intake_check_enabled?(:vagas) && @habitation.vagas_qtd.nil?
          missing << "Informe o box da vaga." if intake_check_enabled?(:box) && @habitation.vagas_qtd.to_i.positive? && @habitation.numero_box.blank?
        end
        missing << "Informe a ocupação do imóvel." if intake_check_enabled?(:ocupacao) && !@habitation.property_kind_terreno? && @habitation.ocupacao_status.blank?
        missing << "Informe a situação do imóvel." if intake_check_enabled?(:situacao) && !@habitation.property_kind_terreno? && @habitation.situacao.blank?
        missing << "Marque ao menos uma característica do imóvel." if @habitation.caracteristicas.blank?
        missing
      when "infraestrutura"
        missing = []
        missing << "Marque ao menos uma característica do edifício." if @habitation.uses_building_infrastructure? && @habitation.infra_estrutura.blank?
        missing
      when "negociacao"
        missing = []
        if @habitation.requires_sale_price? && !@habitation.valid_intake_sale_price?
          missing << @habitation.intake_sale_price_requirement_message
        end
        if @habitation.requires_rent_price? && !@habitation.valid_intake_rent_price?
          missing << @habitation.intake_rent_price_requirement_message
        end
        missing << "Informe ao menos condomínio ou IPTU." if intake_check_enabled?(:financeiro) && @habitation.requires_intake_expense_amount? && @habitation.valor_condominio_cents.blank? && @habitation.valor_iptu_cents.blank?
        missing << "Informe se aceita permuta." if intake_check_enabled?(:permuta) && @habitation.sale_intake? && @habitation.aceita_permuta_answer.blank?
        if intake_check_enabled?(:admin_locacao) && @habitation.rental_intake? && @habitation.salute_rental_management_answer.blank?
          missing << "Informe se a administração da locação será feita internamente."
        end
        missing << "Informe o meio de garantia locatícia." if intake_check_enabled?(:garantia_locaticia) && @habitation.rental_intake? && @habitation.rental_guarantee_method.blank?
        missing << "Informe em quantas vezes aceita parcelamento." if intake_check_enabled?(:parcelamento) && @habitation.aceita_parcelamento_flag? && @habitation.numero_prestacoes.blank?
        missing
      when "fotos"
        missing = []
        missing << "Escolha se vai enviar fotos ou agendar fotógrafo." if @habitation.photo_flow_choice.blank?
        missing << "Envie ao menos uma foto do imóvel." if @habitation.photo_flow_choice == "upload" && !@habitation.has_any_photo?
        missing << "Informe a data/hora agendada com fotógrafo." if @habitation.photo_flow_choice.in?(%w[schedule google_calendar]) && @habitation.photo_session_requested_at.blank?
        missing << "Escolha um horário disponível para a fotografia." if photo_schedule_slot_unavailable?
        missing << "Anexe a autorização do proprietário." unless @habitation.autorizacoes_venda.attached?
        missing
      when "visitas"
        missing = []
        missing << "Informe onde estão as chaves." if intake_check_enabled?(:chaves) && @habitation.requires_intake_key_location? && @habitation.key_location.blank?
        missing << "Informe os melhores dias/horários para visita." if !@habitation.skip_visitas? && !@habitation.intake_visit_days_present?
        missing
      else
        []
      end
    end

    def notify_review_events(records, event:, notes: nil, return_reason: nil)
      Array(records).each do |habitation|
        HabitationIntakeReviewNotifier.new(
          habitation: habitation,
          actor: current_admin_user,
          event: event,
          notes: notes,
          return_reason: return_reason
        ).call
      end
    end

    def invalid_fields_for_step(step)
      fields = {}
      case step
      when "proprietario"
        fields[:proprietario_nome] = true if @habitation.proprietario.blank?
        fields[:proprietario_telefone] = true if @habitation.proprietario_celular.blank?
        fields[:proprietario_cidade] = true if intake_check_enabled?(:proprietario_cidade) && @habitation.proprietario_cidade.blank?
      when "endereco"
        fields[:zip_code] = true if @habitation.cep.blank?
        fields[:street] = true if @habitation.logradouro.blank?
        fields[:street_number] = true if @habitation.numero.blank?
        fields[:neighborhood] = true if @habitation.bairro.blank?
        fields[:city] = true if @habitation.cidade.blank?
        fields[:state] = true if @habitation.uf.blank?
        fields[:edificio_nome] = true if intake_check_enabled?(:empreendimento) && @habitation.requires_intake_development_name? && @habitation.nome_empreendimento.blank?
        fields[:unidade_numero] = true if intake_check_enabled?(:unidade) && @habitation.requires_unit_number? && @habitation.bloco.blank?
        fields[:complemento] = true if @habitation.requires_intake_address_complement? && !@habitation.requires_unit_number? && @habitation.complemento.blank?
      when "caracteristicas"
        if @habitation.property_kind_terreno? && !@habitation.has_required_intake_area?
          fields[:area_total] = true
        elsif !@habitation.has_required_intake_area?
          fields[:area_privativa] = true
        end
        fields[:dormitorios] = true if @habitation.property_kind_residencial? && @habitation.dormitorios_qtd.to_i <= 0
        fields[:banheiros] = true if @habitation.property_kind_residencial? && @habitation.banheiros_qtd.to_i <= 0
        if @habitation.requires_parking_info?
          fields[:tipo_vaga] = true if intake_check_enabled?(:tipo_vaga) && @habitation.tipo_vaga.blank?
          fields[:vagas_garagem] = true if intake_check_enabled?(:vagas) && @habitation.vagas_qtd.nil?
          fields[:numero_box] = true if intake_check_enabled?(:box) && @habitation.vagas_qtd.to_i.positive? && @habitation.numero_box.blank?
        end
        fields[:ocupacao] = true if intake_check_enabled?(:ocupacao) && !@habitation.property_kind_terreno? && @habitation.ocupacao_status.blank?
        fields[:situacao_imovel] = true if intake_check_enabled?(:situacao) && !@habitation.property_kind_terreno? && @habitation.situacao.blank?
        fields[:caracteristicas_imovel] = true if @habitation.caracteristicas.blank?
      when "infraestrutura"
        fields[:caracteristicas_predio] = true if @habitation.uses_building_infrastructure? && @habitation.infra_estrutura.blank?
      when "negociacao"
        fields[:valor_venda] = true if @habitation.requires_sale_price? && !@habitation.valid_intake_sale_price?
        fields[:valor_locacao] = true if @habitation.requires_rent_price? && !@habitation.valid_intake_rent_price?
        if intake_check_enabled?(:financeiro) && @habitation.requires_intake_expense_amount? && @habitation.valor_condominio_cents.blank? && @habitation.valor_iptu_cents.blank?
          fields[:valor_condominio] = true
          fields[:valor_iptu] = true
        end
        fields[:aceita_permuta_answer] = true if intake_check_enabled?(:permuta) && @habitation.sale_intake? && @habitation.aceita_permuta_answer.blank?
        fields[:salute_rental_management_answer] = true if intake_check_enabled?(:admin_locacao) && @habitation.rental_intake? && @habitation.salute_rental_management_answer.blank?
        fields[:rental_guarantee_method] = true if intake_check_enabled?(:garantia_locaticia) && @habitation.rental_intake? && @habitation.rental_guarantee_method.blank?
        fields[:numero_prestacoes] = true if intake_check_enabled?(:parcelamento) && @habitation.aceita_parcelamento_flag? && @habitation.numero_prestacoes.blank?
      when "fotos"
        fields[:photo_flow_choice] = true if @habitation.photo_flow_choice.blank?
        fields[:photos] = true if @habitation.photo_flow_choice == "upload" && !@habitation.has_any_photo?
        fields[:photo_session_requested_at] = true if @habitation.photo_flow_choice.in?(%w[schedule google_calendar]) && @habitation.photo_session_requested_at.blank?
        fields[:photo_session_requested_at] = true if photo_schedule_slot_unavailable?
        fields[:autorizacoes_venda] = true unless @habitation.autorizacoes_venda.attached?
      when "visitas"
        fields[:chaves_com] = true if intake_check_enabled?(:chaves) && @habitation.requires_intake_key_location? && @habitation.key_location.blank?
        fields[:dias_visitas] = true if !@habitation.skip_visitas? && !@habitation.intake_visit_days_present?
      end
      fields
    end

    def photo_schedule_slot_unavailable?
      return false unless @habitation.photo_flow_choice.in?(%w[schedule google_calendar])
      return false if @habitation.photo_session_requested_at.blank?

      scheduled_at = @habitation.photo_session_requested_at.in_time_zone("America/Sao_Paulo")
      return true if scheduled_at.to_date <= Date.current
      return true if PhotographyScheduleBlock.exists?(date: scheduled_at.to_date)
      return true if local_photo_schedule_conflict?(scheduled_at)
      return false unless @google_calendar_setting&.configured?

      GoogleCalendar::AvailabilityReader.new(
        setting: @google_calendar_setting,
        tenant: current_tenant,
        start_date: scheduled_at.to_date,
        days: 1
      ).busy_at?(scheduled_at)
    rescue StandardError => e
      Rails.logger.warn("[intake] validar disponibilidade Google Calendar falhou: #{e.class}: #{e.message}")
      false
    end

    def local_photo_schedule_conflict?(scheduled_at)
      current_tenant.habitations
        .broker_intakes
        .where(photo_flow_choice: %w[schedule google_calendar])
        .where.not(id: @habitation&.id)
        .where(photo_session_requested_at: scheduled_at.beginning_of_minute)
        .exists?
    end

    def duplicate_address_blocks_intake?(step)
      return false unless step.in?(%w[endereco review])

      duplicate_address_result.complete && duplicate_address_result.duplicate?
    end

    def duplicate_address_result
      @duplicate_address_result ||= HabitationDuplicateChecker.new(
        street: @habitation.logradouro,
        number: @habitation.numero,
        building: @habitation.nome_empreendimento,
        unit: @habitation.bloco,
        status: @habitation.status,
        complement: @habitation.complemento,
        category: @habitation.categoria,
        comparison: @habitation.duplicate_identity_scope,
        ignored_id: @habitation.id,
        tenant: Current.tenant
      ).call
    end

    def assign_duplicate_address_errors
      duplicated = duplicate_address_result.matches.first
      code = duplicated&.codigo.present? ? " ##{duplicated.codigo}" : ""
      message = if @habitation.duplicate_identity_scope == :unit
                  "Já existe imóvel cadastrado com esta rua, número, unidade e status comercial#{code}."
                else
                  "Já existe imóvel cadastrado com esta rua, número e status comercial#{code}."
                end
      @invalid_fields ||= {}
      @invalid_fields[:street] = true
      @invalid_fields[:street_number] = true
      @invalid_fields[:unidade_numero] = true if @habitation.duplicate_identity_scope == :unit
      @step_errors ||= []
      @step_errors << message
      @missing_requirements ||= []
      @missing_requirements << message
      @habitation.errors.add(:base, message)
    end

    def published_restricted_update?
      @habitation.intake_published? && !can?(:manage, :imoveis)
    end

    def published_restricted_params
      captacao_style_params.except(*published_locked_fields.map(&:to_s))
    end

    def published_locked_fields
      %i[
        nome_empreendimento
        titulo_anuncio
        descricao_web
        descricao_interna
        proprietario
        proprietario_celular
        proprietario_email
        proprietario_codigo
        proprietario_telefone_comercial
        proprietario_telefone_residencial
        proprietor_id
        address_attributes
      ]
    end

    def intake_param_key
      return :habitation if params[:habitation].present?
      return :captacao if params[:captacao].present?
    end

    def captacao_style_params
      normalize_rental_guarantee_method_param!(:habitation)
      normalize_rental_guarantee_method_param!(:captacao)

      permitted_keys = [
        :categoria, :status, :situacao, :tipo, :codigo_empreendimento, :nome_empreendimento, :titulo_anuncio,
        :property_kind, :modalidade, :step,
        :dormitorios_qtd, :suites_qtd, :banheiros_qtd, :vagas_qtd, :elevadores_qtd,
        :area_total, :area_privativa, :dormitorios, :suites, :demi_suites, :salas, :banheiros, :vagas_garagem,
        :ocupacao, :estado_imovel, :situacao_imovel, :sacada, :terraco, :dependencia_empregada, :precisa_reforma,
        :andares_total, :aptos_por_andar, :distancia_praia,
        :area_privativa_m2, :area_total_m2, :area_terreno_m2, :area_util_m2,
        :valor_venda, :valor_locacao, :valor_condominio, :valor_iptu, :saldo_devedor,
        :valor_venda_formatted, :valor_locacao_formatted, :valor_condominio_formatted,
        :valor_iptu_formatted, :saldo_devedor_formatted,
        :motivo_venda, :cidade_permuta, :aceita_parcelamento,
        :descricao_web, :descricao_interna, :observacoes, :condicoes_negociacao, :observacoes_visitas,
        :proprietario_nome, :proprietario_telefone, :proprietario_cpf_cnpj, :proprietario_cidade,
        :proprietario, :proprietario_celular, :proprietario_email,
        :proprietario_telefone_comercial, :proprietario_telefone_residencial,
        :proprietario_codigo, :proprietor_id, :admin_user_id,
        :photo_flow_choice, :photo_session_requested_at, :photo_session_url,
        :salute_rental_management_answer, :aceita_permuta_answer,
        :aceita_parcelamento_flag, :numero_prestacoes, :aceita_financiamento_flag,
        :aceita_permuta_veiculo_flag, :aceita_permuta_imovel_flag, :aceita_permuta_outros_flag,
        :mobiliado_flag, :exclusivo_flag, :ocupacao_status, :estado_conservacao,
        :andar, :ano_construcao, :demi_suites_qtd, :numero_box, :tipo_vaga,
        :dimensoes_terreno, :topografia, :key_location, :key_location_notes,
        :corretor_nome, :corretor_telefone, :corretor_email, :ordered_photo_ids,
        :zip_code, :street, :street_number, :neighborhood, :city, :state, :complemento, :edificio_nome, :unidade_numero,
        :lote, :quadra,
        :chaves_com, :senha_imovel, :senha_portaria,
        { rental_guarantee_method: [],
          caracteristicas: [], infra_estrutura: [], caracteristica_unica: [],
          caracteristicas_imovel: [], caracteristicas_predio: [], aceita_permuta: [], outras_taxas: [], dias_visitas: [],
          photos: [], fotos: [], autorizacoes_venda: [], fichas_cadastro: [], autorizacao_pdf: [],
          extras: {},
          address_attributes: [:id, :tipo_endereco, :logradouro, :numero, :complemento, :bairro, :bairro_comercial, :cidade, :uf, :cep, :pais, :latitude, :longitude, :_destroy, { imediacoes: [] }] }
      ]
      raw = ActionController::Parameters.new
      raw.deep_merge!(params[:habitation].permit(*permitted_keys)) if params[:habitation].present?
      raw.deep_merge!(params[:captacao].permit(*permitted_keys)) if params[:captacao].present?
      # Re-aplica o allow-list ao merge (em vez de permit!, que liberava
      # QUALQUER atributo não listado — ex.: admin_user_id, flags de status).
      normalize_captacao_params(raw.permit(*permitted_keys))
    end

    def normalize_captacao_params(raw)
      attrs = raw.to_h
      attrs = filter_returnable_intake_params(attrs)
      normalize_attachment_params!(attrs)
      attrs["intake_step"] = attrs.delete("step") if attrs["step"].present?
      cadastro_type = attrs.delete("cadastro_type")
      property_kind = attrs.delete("property_kind")
      default_category = default_category_for_cadastro_type(cadastro_type.presence || property_kind)
      attrs["categoria"] = default_category if attrs["categoria"].blank? && default_category.present?
      if (modalidade = attrs.delete("modalidade")).present?
        attrs["intake_modalidade"] = modalidade
        attrs["status"] = modalidade.in?(%w[locacao_anual locacao_diaria]) ? "Aluguel" : "Venda"
      end
      attrs["proprietario"] = attrs.delete("proprietario_nome") if attrs["proprietario_nome"].present?
      attrs["proprietario_celular"] = attrs.delete("proprietario_telefone") if attrs["proprietario_telefone"].present?
      attrs["proprietario_codigo"] = attrs.delete("proprietario_cpf_cnpj") if attrs["proprietario_cpf_cnpj"].present?
      normalize_intake_proprietor_fields!(attrs)
      attrs["area_total_m2"] = attrs.delete("area_total") if attrs["area_total"].present?
      attrs["area_privativa_m2"] = attrs.delete("area_privativa") if attrs["area_privativa"].present?
      attrs["dormitorios_qtd"] = attrs.delete("dormitorios") if attrs["dormitorios"].present?
      attrs["suites_qtd"] = attrs.delete("suites") if attrs["suites"].present?
      attrs["demi_suites_qtd"] = attrs.delete("demi_suites") if attrs["demi_suites"].present?
      attrs["salas_qtd"] = attrs.delete("salas") if attrs["salas"].present?
      attrs["banheiros_qtd"] = attrs.delete("banheiros") if attrs["banheiros"].present?
      attrs["vagas_qtd"] = attrs.delete("vagas_garagem") if attrs["vagas_garagem"].present?
      attrs["andares_qtd"] = attrs.delete("andares_total") if attrs["andares_total"].present?
      attrs["aptos_andar"] = attrs.delete("aptos_por_andar") if attrs["aptos_por_andar"].present?
      attrs["valor_venda_formatted"] = attrs.delete("valor_venda") if attrs["valor_venda"].present?
      attrs["valor_locacao_formatted"] = attrs.delete("valor_locacao") if attrs["valor_locacao"].present?
      attrs["valor_condominio_formatted"] = attrs.delete("valor_condominio") if attrs["valor_condominio"].present?
      attrs["valor_iptu_formatted"] = attrs.delete("valor_iptu") if attrs["valor_iptu"].present?
      attrs["saldo_devedor_formatted"] = attrs.delete("saldo_devedor") if attrs["saldo_devedor"].present?
      attrs["nome_empreendimento"] = attrs.delete("edificio_nome") if attrs["edificio_nome"].present?
      attrs["bloco"] = attrs.delete("unidade_numero") if attrs["unidade_numero"].present?
      normalize_street_house_category!(attrs)
      attrs["ocupacao_status"] = attrs.delete("ocupacao") if attrs["ocupacao"].present?
      attrs["estado_conservacao"] = attrs.delete("estado_imovel") if attrs["estado_imovel"].present?
      attrs["situacao"] = attrs.delete("situacao_imovel") if attrs["situacao_imovel"].present?
      normalize_intake_feature_fields!(attrs)
      normalize_intake_visit_fields!(attrs)
      attrs["caracteristicas"] = attrs.delete("caracteristicas_imovel") if attrs["caracteristicas_imovel"].present?
      attrs["infra_estrutura"] = attrs.delete("caracteristicas_predio") if attrs["caracteristicas_predio"].present?
      attrs["aceita_permuta_answer"] = Array(attrs.delete("aceita_permuta")).include?("Sim") ? "sim" : "nao" if attrs.key?("aceita_permuta")
      attrs["aceita_parcelamento_flag"] = ActiveModel::Type::Boolean.new.cast(attrs["aceita_parcelamento_flag"]) if attrs.key?("aceita_parcelamento_flag")
      if attrs["aceita_parcelamento"].present?
        attrs["aceita_parcelamento_flag"] = attrs.delete("aceita_parcelamento") != "nao"
      end
      attrs["photos"] = attrs.delete("fotos") if attrs["fotos"].present?
      attrs["autorizacoes_venda"] = Array(attrs.delete("autorizacao_pdf")) if attrs["autorizacao_pdf"].present?
      normalize_intake_land_extra_fields!(attrs)
      address_keys = %w[zip_code street street_number neighborhood city state complemento]
      if address_keys.any? { |key| attrs.key?(key) }
        attrs["address_attributes"] = {
          cep: attrs.delete("zip_code"),
          logradouro: attrs.delete("street"),
          numero: attrs.delete("street_number"),
          complemento: attrs.delete("complemento"),
          bairro: attrs.delete("neighborhood"),
          cidade: attrs.delete("city"),
          uf: attrs.delete("state")
        }.compact_blank
        attrs["address_attributes"]["id"] = @habitation.address.id if @habitation.address.present?
      end
      attrs.except("salas", "sacada", "terraco", "dependencia_empregada", "precisa_reforma", "distancia_praia", "cidade_permuta", "outras_taxas", "dias_visitas", "extras", "proprietario_cidade")
    end

    def filter_returnable_intake_params(attrs)
      return attrs unless @habitation&.intake_returned_to_broker?
      return attrs if can?(:review, :captacoes)

      allowed_fields = @property_setting&.available_returnable_field_names || []
      attrs.slice(*allowed_fields)
    end

    def normalize_intake_feature_fields!(attrs)
      features = Array(attrs["caracteristicas_imovel"].presence || @habitation.caracteristicas).compact_blank
      touched = false
      {
        "sacada" => "Sacada",
        "terraco" => "Terraço",
        "dependencia_empregada" => "Dependência de empregada",
        "precisa_reforma" => "Precisa reforma"
      }.each do |param_key, label|
        next unless attrs.key?(param_key)

        touched = true
        enabled = ActiveModel::Type::Boolean.new.cast(attrs.delete(param_key))
        features = features.reject { |feature| feature.to_s.casecmp?(label) }
        features << label if enabled
      end
      attrs["caracteristicas_imovel"] = features if touched || features.present?
    end

    def normalize_intake_proprietor_fields!(attrs)
      return unless attrs.key?("proprietario_cidade")

      notes = attrs["observacoes_visitas"].presence || @habitation.observacoes_visitas
      attrs["observacoes_visitas"] = upsert_captacao_note(notes, "Cidade do proprietário", attrs.delete("proprietario_cidade"))
    end

    def normalize_intake_visit_fields!(attrs)
      if attrs.key?("chaves_com")
        attrs["key_location"] = key_location_from_captacao_value(attrs.delete("chaves_com"))
      end

      notes = attrs.key?("observacoes_visitas") ? attrs["observacoes_visitas"] : @habitation.observacoes_visitas
      notes = upsert_captacao_note(notes, "Outras taxas", Array(attrs.delete("outras_taxas")).compact_blank.join(", ")) if attrs.key?("outras_taxas")
      notes = upsert_captacao_note(notes, "Dias/horários para visita", Array(attrs.delete("dias_visitas")).compact_blank.join(", ")) if attrs.key?("dias_visitas")
      notes = upsert_captacao_note(notes, "Senha do imóvel", attrs.delete("senha_imovel")) if attrs.key?("senha_imovel")
      notes = upsert_captacao_note(notes, "Senha da portaria", attrs.delete("senha_portaria")) if attrs.key?("senha_portaria")
      if attrs.key?("distancia_praia")
        distance = attrs.delete("distancia_praia")
        notes = upsert_captacao_note(notes, "Distância da praia", distance.present? ? "#{distance} m" : nil)
      end
      attrs["observacoes_visitas"] = notes if attrs.key?("observacoes_visitas") || notes.present?
    end

    def normalize_intake_land_extra_fields!(attrs)
      extras = attrs.delete("extras")
      return unless extras.is_a?(Hash)

      if extras["topografia"].present?
        attrs["topografia"] = {
          "plano" => "Plano",
          "aclive" => "Aclive",
          "declive" => "Declive",
          "irregular" => "Irregular"
        }.fetch(extras["topografia"], extras["topografia"])
      end
      attrs["face"] = extras["face"] if extras["face"].present?
      return if extras["frente_metros"].blank?

      existing_parts = attrs["dimensoes_terreno"].presence || @habitation.dimensoes_terreno.to_s
      parts = existing_parts.split("|").map(&:strip).reject { |part| part.start_with?("Frente:") }.compact_blank
      parts.unshift("Frente: #{extras['frente_metros']} m")
      attrs["dimensoes_terreno"] = parts.join(" | ")
    end


    def key_location_from_captacao_value(value)
      {
        "corretor" => "Corretor(a)",
        "proprietario" => "Proprietário",
        "portaria" => "Portaria",
        "outro" => "Outro"
      }[value.to_s]
    end

    def upsert_captacao_note(text, label, value)
      lines = text.to_s.lines.map(&:chomp).reject { |line| line.start_with?("#{label}:") }
      lines << "#{label}: #{value}" if value.present?
      lines.join("\n")
    end

    def default_category_for_cadastro_type(value)
      case value
      when "apartamentos" then "Apartamento"
      when "residencial", "imoveis_residenciais" then "Casa"
      when "comerciais_industriais", "sala_comercial" then "Sala Comercial"
      when "terrenos", "terreno" then "Terreno"
      end
    end

    def normalize_street_house_category!(attrs)
      return if attrs["bloco"].present?

      building_name = attrs["nome_empreendimento"].to_s.strip
      return unless building_name.match?(/\Acasa\z/i)
      return if attrs["categoria"].present? && !attrs["categoria"].to_s.match?(/apartamento/i)

      attrs["categoria"] = "Casa"
    end

    def normalize_attachment_params!(attrs)
      %w[photos fotos autorizacoes_venda fichas_cadastro autorizacao_pdf].each do |key|
        next unless attrs.key?(key)

        values = Array(attrs[key]).reject { |value| value.respond_to?(:blank?) ? value.blank? : value.nil? }
        if values.any?
          attrs[key] = values
        else
          attrs.delete(key)
        end
      end
    end

    def submission_notice(submitted_records, target_intake_status = "submitted_for_admin_review")
      return "Captação aprovada para publicação." if target_intake_status == "admin_approved"
      return "Captação enviada para aprovação administrativa." if submitted_records.size == 1

      "Captação enviada para aprovação administrativa. Foram gerados cadastros separados para venda e locação."
    end

    def sale_reason_options
      catalog_options = current_tenant.attribute_options.where(context: "habitation", category: "sale_reason").order(:name).pluck(:name)
      habitation_options = if Habitation.column_names.include?("motivo_venda")
                             current_tenant.habitations.where.not(motivo_venda: [nil, ""]).distinct.pluck(:motivo_venda)
                           else
                             []
                           end
      captacao_options = if defined?(Captacao) && Captacao.column_names.include?("motivo_venda")
                           # Captação não tem tenant_id: escopa pela conta via corretor (AdminUser).
                           Captacao.where(corretor_id: current_tenant.admin_users.select(:id))
                                   .where.not(motivo_venda: [nil, ""]).distinct.pluck(:motivo_venda)
                         else
                           []
                         end

      (catalog_options + habitation_options + captacao_options).map { |reason| reason.to_s.strip }.reject(&:blank?).uniq.sort
    end
  end
end
