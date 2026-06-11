class Admin::SeoSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_seo_setting, only: [:edit, :update, :destroy, :generate_ai, :toggle]
  before_action :load_editor_helpers, only: [:edit]

  def index
    @seo_settings = SeoSetting
                    .order(last_accessed_at: :desc, access_count: :desc, page_name: :asc)
                    .paginate(page: params[:page], per_page: 20)
    @seo_strategy_prompt = Ai::SeoContentService.instructions
    @auto_inventory_enabled = Seo::PageTracker.enabled?
    @auto_apply_enabled = Seo::PageTracker.auto_apply?
    @auto_ai_enabled = Seo::PageTracker.auto_ai?
    @seo_discovery_status = Seo::DiscoveryService.status
    @seo_discovery_enabled = Seo::DiscoveryService.enabled?
    @stats = {
      total: SeoSetting.count,
      active: SeoSetting.where(active: true).count,
      public: SeoSetting.where(apply_to_public: true).count,
      generated: SeoSetting.where(ai_status: "generated").count
    }
  end

  def new
    @seo_setting = SeoSetting.new
  end

  def create
    @seo_setting = SeoSetting.new(seo_setting_params)
    if @seo_setting.save
      @seo_setting.sync_focus_keywords!(params[:seo_setting][:focus_keyword_list])
      redirect_to admin_seo_settings_path, notice: 'SEO criado com sucesso!'
    else
      load_editor_helpers
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @seo_setting.update(seo_setting_params)
      @seo_setting.sync_focus_keywords!(params[:seo_setting][:focus_keyword_list])
      redirect_to edit_admin_seo_setting_path(@seo_setting), notice: 'SEO atualizado!'
    else
      load_editor_helpers
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @seo_setting.destroy
    redirect_to admin_seo_settings_path, notice: 'SEO removido!'
  end

  def update_strategy
    Setting.set(Seo::PageTracker::AUTO_INVENTORY_SETTING, params[:seo_auto_inventory_enabled] == "1" ? "1" : "0", "Criar SEO automaticamente por acesso")
    Setting.set(Seo::PageTracker::AUTO_APPLY_SETTING, params[:seo_auto_apply_enabled] == "1" ? "1" : "0", "Aplicar SEO técnico automaticamente no público")
    Setting.set(Seo::PageTracker::AUTO_AI_SETTING, params[:seo_ai_auto_generate_enabled] == "1" ? "1" : "0", "Gerar SEO com IA automaticamente")
    Seo::DiscoveryService.save_enabled!(params[:seo_discovery_enabled] == "1")
    Ai::SeoContentService.save_instructions!(params[:seo_ai_strategy_prompt])

    redirect_to admin_seo_settings_path, notice: "Estratégia de SEO atualizada."
  end

  def discover
    SeoDiscoveryJob.perform_later(generate_ai: params[:generate_ai] != "0")
    redirect_to admin_seo_settings_path, notice: "Descoberta SEO iniciada em segundo plano."
  end

  def generate_ai
    unless Ai::SeoContentService.connected?
      return render_generate_ai_response(
        alert: "Configure o token da OpenAI em Integrações > IA antes de gerar SEO.",
        status: :unprocessable_entity
      )
    end

    Ai::SeoContentService.new(@seo_setting).generate!
    @seo_setting.reload
    @seo_setting.sync_focus_keywords!(@seo_setting.meta_keywords)

    render_generate_ai_response(notice: "SEO gerado com IA, aplicado aos campos e salvo.")
  rescue => e
    @seo_setting.reload
    render_generate_ai_response(
      alert: "Não foi possível gerar o SEO com IA: #{e.message}",
      status: :unprocessable_entity
    )
  end

  def toggle
    field = params[:field].to_s
    allowed = %w[active apply_to_public manual_mode robots_index robots_follow]
    return redirect_to admin_seo_settings_path, alert: "Campo inválido." unless allowed.include?(field)

    @seo_setting.update!(field => !@seo_setting.public_send("#{field}?"))
    redirect_to admin_seo_settings_path, notice: "Configuração atualizada."
  end

  private

  def set_seo_setting
    @seo_setting = SeoSetting.find(params[:id])
  end

  def load_editor_helpers
    @readability = Seo::ReadabilityAnalyzer.new(@seo_setting).call
    @internal_link_suggestions = Seo::InternalLinkSuggestionService.new(@seo_setting).call
    @change_logs = @seo_setting.change_logs.includes(:admin_user).limit(8)
  end

  def seo_setting_params
    params.require(:seo_setting).permit(
      :page_name,
      :meta_title,
      :meta_description,
      :meta_keywords,
      :og_image,
      :canonical_url,
      :og_image_file,
      :canonical_key,
      :page_type,
      :canonical_path,
      :og_title,
      :og_description,
      :intro_text,
      :robots_index,
      :robots_follow,
      :active,
      :apply_to_public,
      :manual_mode,
      :ai_insights,
      :focus_keyword_list
    )
  end

  def render_generate_ai_response(notice: nil, alert: nil, status: :ok)
    message = notice || alert
    message_type = notice.present? ? "success" : "danger"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "seo-setting-form",
          partial: "admin/seo_settings/form",
          locals: {
            seo_setting: @seo_setting,
            ai_message: message,
            ai_message_type: message_type,
            readability: Seo::ReadabilityAnalyzer.new(@seo_setting).call,
            internal_link_suggestions: Seo::InternalLinkSuggestionService.new(@seo_setting).call,
            change_logs: @seo_setting.change_logs.includes(:admin_user).limit(8)
          }
        ), status: status
      end

      format.html do
        if notice.present?
          redirect_to edit_admin_seo_setting_path(@seo_setting), notice: notice
        else
          redirect_to edit_admin_seo_setting_path(@seo_setting), alert: alert
        end
      end
    end
  end
end
