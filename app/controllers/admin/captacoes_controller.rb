module Admin
  class CaptacoesController < Admin::BaseController
    DASHBOARD_EYEBROW_SETTING = "captacao_dashboard_eyebrow".freeze
    DASHBOARD_TITLE_SETTING = "captacao_dashboard_title".freeze
    DEFAULT_DASHBOARD_EYEBROW = "Palavra do Ano".freeze
    DEFAULT_DASHBOARD_TITLE = "Captação".freeze

    before_action -> { check_permission!(:view, :captacoes) }
    before_action :set_captacao, only: [:edit, :update, :show, :destroy, :publish]
    before_action :authorize_access!, only: [:edit, :update, :show, :destroy, :publish]

    layout :resolve_layout

    def dashboard
      set_dashboard_title

      @period_start = parse_date(params[:start_date]) || Date.current.beginning_of_year
      @period_end   = parse_date(params[:end_date])   || Date.current
      @month_filter = params[:month].presence
      @target_month_label = target_month_label(@month_filter)

      scope = captacao_habitation_scope
      scope = scope.where("EXTRACT(MONTH FROM COALESCE(habitations.data_cadastro_crm, habitations.created_at)) = ?", @month_filter.to_i) if @month_filter.present?
      scope = scope.where(admin_user_id: current_admin_user.id) unless owns_all_resource?(:captacoes)

      venda_scope = scope.where("COALESCE(habitations.valor_venda_cents, 0) > 0")
      locacao_scope = scope.where("COALESCE(habitations.valor_locacao_cents, 0) > 0")

      @total_venda   = venda_scope.count
      @total_locacao = locacao_scope.count

      @meta_venda   = CaptacaoGoal.current_target(start_date: @period_start, end_date: @period_end, kind: :venda)
      @meta_locacao = CaptacaoGoal.current_target(start_date: @period_start, end_date: @period_end, kind: :locacao)

      @publicado_venda   = venda_scope.where(exibir_no_site_flag: true).count
      @nao_publicado_venda = @total_venda - @publicado_venda

      @publicado_locacao   = locacao_scope.where(exibir_no_site_flag: true).count
      @nao_publicado_locacao = @total_locacao - @publicado_locacao

      @total_valor_venda   = venda_scope.sum(:valor_venda_cents).to_f / 100.0
      @total_valor_locacao = locacao_scope.sum(:valor_locacao_cents).to_f / 100.0

      @ranking_venda = venda_scope
        .left_joins(:admin_user)
        .group("admin_users.id", "admin_users.name")
        .select("admin_users.id, COALESCE(admin_users.name, 'Sem corretor') AS name, COUNT(habitations.id) AS ct, COALESCE(SUM(habitations.valor_venda_cents),0) / 100.0 AS total_value")
        .order("ct DESC, total_value DESC")
        .limit(15)

      @ranking_locacao = locacao_scope
        .left_joins(:admin_user)
        .group("admin_users.id", "admin_users.name")
        .select("admin_users.id, COALESCE(admin_users.name, 'Sem corretor') AS name, COUNT(habitations.id) AS ct, COALESCE(SUM(habitations.valor_locacao_cents),0) / 100.0 AS total_value")
        .order("ct DESC, total_value DESC")
        .limit(15)

      @goal_venda_obj   = CaptacaoGoal.current_foco(start_date: @period_start, end_date: @period_end, kind: :venda)
      @goal_locacao_obj = CaptacaoGoal.current_foco(start_date: @period_start, end_date: @period_end, kind: :locacao)
      @regiao_foco_venda = venda_scope.where(regiao_foco_positive_condition).count
      @regiao_foco_locacao = locacao_scope.where(regiao_foco_positive_condition).count
      @captacao_adm_locacao = locacao_scope.where(salute_rental_management_flag: true).count
      @regiao_foco_venda_percent = percentage(@regiao_foco_venda, @total_venda)
      @regiao_foco_locacao_percent = percentage(@regiao_foco_locacao, @total_locacao)
      @captacao_adm_locacao_percent = percentage(@captacao_adm_locacao, @total_locacao)

      intake_scope = Habitation.broker_intakes.where(created_at: @period_start.beginning_of_day..@period_end.end_of_day)
      intake_scope = intake_scope.where("EXTRACT(MONTH FROM habitations.created_at) = ?", @month_filter.to_i) if @month_filter.present?
      intake_scope = intake_scope.where(admin_user_id: current_admin_user.id) unless owns_all_resource?(:pre_cadastros) || can?(:review, :pre_cadastros)

      @pre_cadastro_total = intake_scope.count
      @pre_cadastro_draft = intake_scope.where(intake_status: [nil, "draft", "returned_to_broker"]).count
      @pre_cadastro_review = intake_scope.where(intake_status: "submitted_for_admin_review").count
      @pre_cadastro_admin_approved = intake_scope.where(intake_status: "admin_approved").count
      @pre_cadastro_published = intake_scope.where(intake_status: "published").count

      build_leads_heatmap
    end

    def update_dashboard_title
      require_admin!
      return if performed?

      attrs = dashboard_title_params
      Setting.set(DASHBOARD_EYEBROW_SETTING, attrs[:eyebrow].to_s.strip.presence || DEFAULT_DASHBOARD_EYEBROW, "Texto superior do dashboard de captação")
      Setting.set(DASHBOARD_TITLE_SETTING, attrs[:title].to_s.strip.presence || DEFAULT_DASHBOARD_TITLE, "Título principal do dashboard de captação")

      redirect_to dashboard_admin_captacoes_path, notice: "Título do dashboard atualizado."
    end

    def index
      @captacoes = scoped_captacoes
      @captacoes = @captacoes.where(property_kind: params[:property_kind]) if params[:property_kind].present?
      case params[:status]
      when "draft"       then @captacoes = @captacoes.draft
      when "completed"   then @captacoes = @captacoes.done
      when "published"   then @captacoes = @captacoes.where(published_on_site: true)
      end
      @captacoes = @captacoes.includes(:corretor).order(updated_at: :desc).paginate(page: params[:page], per_page: 20)
    end

    def new
      captacao = Captacao.create!(
        corretor: current_admin_user,
        step: "intro",
        modalidade: default_modalidade,
        proprietario_cidade: current_admin_user.default_store&.city
      )
      redirect_to edit_admin_captacao_path(captacao)
    end

    def edit
      @step = params[:step].presence_in(Captacao::STEPS) || @captacao.step
      # Terreno pula o step de visitas
      @step = @captacao.next_step if @step == "visitas" && @captacao.skip_visitas?
    end

    def update
      current_step = params[:current_step].presence_in(Captacao::STEPS) || @captacao.step
      direction    = params[:direction].to_s

      if direction == "back"
        target = @captacao.previous_step || current_step
        target = target == "visitas" && @captacao.skip_visitas? ? Captacao::STEPS[Captacao::STEPS.index("visitas") - 1] : target
        @captacao.assign_attributes(captacao_params) if params[:captacao].present?
        @captacao.update_column(:step, target)
        redirect_to edit_admin_captacao_path(@captacao, step: target)
        return
      end

      @captacao.assign_attributes(captacao_params) if params[:captacao].present?

      if @captacao.save(context: current_step.to_sym)
        if current_step == "review"
          @captacao.update_columns(completed: true, submitted_at: Time.current)
          redirect_to admin_captacao_path(@captacao), notice: "Captação finalizada com sucesso."
        else
          next_step = @captacao.next_step
          next_step = @captacao.next_step if next_step == "visitas" && @captacao.skip_visitas?
          next_step = next_step_after_skipping_visitas(next_step)
          @captacao.update_column(:step, next_step)
          redirect_to edit_admin_captacao_path(@captacao, step: next_step)
        end
      else
        @step = current_step
        render :edit, status: :unprocessable_entity
      end
    end

    def show
    end

    def destroy
      if @captacao.completed?
        redirect_to admin_captacoes_path, alert: "Só rascunhos podem ser removidos."
      else
        @captacao.destroy
        redirect_to admin_captacoes_path, notice: "Rascunho removido."
      end
    end

    def publish
      @captacao.update!(published_on_site: !@captacao.published_on_site)
      redirect_to admin_captacao_path(@captacao),
                  notice: @captacao.published_on_site? ? "Captação marcada como publicada." : "Publicação desmarcada."
    end

    private

    def set_dashboard_title
      @dashboard_eyebrow = Setting.get(DASHBOARD_EYEBROW_SETTING, DEFAULT_DASHBOARD_EYEBROW)
      @dashboard_title = Setting.get(DASHBOARD_TITLE_SETTING, DEFAULT_DASHBOARD_TITLE)
    end

    def dashboard_title_params
      params.require(:dashboard).permit(:eyebrow, :title)
    end

    def require_admin!
      return if current_admin_user.admin?

      redirect_to dashboard_admin_captacoes_path, alert: "Você não tem permissão para alterar o dashboard."
    end

    def captacao_habitation_scope
      Habitation
        .where("COALESCE(habitations.tipo, '') <> 'Empreendimento'")
        .where("COALESCE(habitations.data_cadastro_crm, habitations.created_at) BETWEEN ? AND ?", @period_start.beginning_of_day, @period_end.end_of_day)
    end

    def percentage(value, total)
      return 0 if total.to_i.zero?

      ((value.to_f / total.to_f) * 100).round
    end

    def regiao_foco_positive_condition
      [
        "NULLIF(TRIM(habitations.regiao_foco), '') IS NOT NULL " \
        "AND habitations.regiao_foco != '.' " \
        "AND unaccent(habitations.regiao_foco) NOT ILIKE unaccent('Nao') " \
        "AND unaccent(habitations.regiao_foco) NOT ILIKE unaccent('Sem preferência')"
      ]
    end

    def set_captacao
      @captacao = Captacao.find(params[:id])
    end

    def parse_date(str)
      return nil if str.blank?
      Date.parse(str) rescue nil
    end

    def target_month_label(month)
      return "Todos" if month.blank?

      I18n.l(Date.new(Date.current.year, month.to_i), format: "%B").capitalize
    rescue ArgumentError
      "Todos"
    end

    def build_leads_heatmap
      leads = Lead.where(created_at: @period_start.beginning_of_day..@period_end.end_of_day)
                  .where.not(admin_user_id: nil)
      leads = leads.where(lead_type: params[:lead_category]) if params[:lead_category].present?
      leads = leads.where(origin: params[:lead_source])      if params[:lead_source].present?
      leads = leads.where(admin_user_id: current_admin_user.id) unless current_admin_user.admin?

      rows = leads.group(:admin_user_id, "DATE(created_at)").count

      user_ids = rows.keys.map(&:first).uniq
      @heatmap_corretores = AdminUser.where(id: user_ids).order(:name).to_a
      @heatmap_dates = (@period_start.to_date..@period_end.to_date).to_a

      # Monta hash { admin_user_id => { date => count } }
      @heatmap_matrix = Hash.new { |h, k| h[k] = Hash.new(0) }
      rows.each do |(uid, date), count|
        dt = date.is_a?(Date) ? date : Date.parse(date.to_s)
        @heatmap_matrix[uid][dt] = count
      end

      @heatmap_max = rows.values.max || 0

      # Opções dos filtros
      @lead_categories = Lead.distinct.pluck(:lead_type).compact.sort
      @lead_sources    = Lead.distinct.pluck(:origin).compact.sort
    end

    def authorize_access!
      return if owns_all_resource?(:captacoes)
      return if @captacao.corretor_id == current_admin_user.id
      redirect_to admin_captacoes_path, alert: "Você não tem acesso a esta captação."
    end

    def scoped_captacoes
      owns_all_resource?(:captacoes) ? Captacao.all : Captacao.where(corretor: current_admin_user)
    end

    def resolve_layout
      action_name.in?(%w[new edit update]) ? "captacao_wizard" : "admin"
    end

    def default_modalidade
      case current_admin_user.acting_type
      when "rentals" then :locacao_anual
      when "sales"   then :venda
      else :venda
      end
    end

    def next_step_after_skipping_visitas(candidate)
      return candidate unless candidate == "visitas" && @captacao.skip_visitas?
      Captacao::STEPS[Captacao::STEPS.index("visitas") + 1]
    end

    def captacao_params
      params.require(:captacao).permit(
        :property_kind, :modalidade,
        :proprietario_nome, :proprietario_telefone, :proprietario_cpf_cnpj,
        :proprietario_email, :proprietario_cidade,
        :zip_code, :street, :street_number, :neighborhood, :city, :state,
        :edificio_nome, :unidade_numero, :latitude, :longitude,
        :dormitorios, :suites, :demi_suites, :salas, :banheiros, :vagas_garagem,
        :area_privativa, :area_total, :ocupacao, :estado_imovel, :situacao_imovel,
        :precisa_reforma, :sacada, :terraco, :dependencia_empregada,
        :andares_total, :aptos_por_andar, :distancia_praia,
        :valor_venda, :valor_locacao, :valor_condominio, :valor_iptu,
        :saldo_devedor, :cidade_permuta, :aceita_parcelamento, :motivo_venda,
        :chaves_com, :senha_imovel, :senha_portaria, :observacoes,
        :autorizacao_pdf,
        caracteristicas_imovel: [],
        caracteristicas_predio: [],
        outras_taxas: [],
        aceita_permuta: [],
        dias_visitas: [],
        fotos: [],
        extras: {}
      )
    end
  end
end
