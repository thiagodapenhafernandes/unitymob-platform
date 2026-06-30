class Admin::WhatsappTemplatesController < Admin::BaseController
  before_action -> { check_permission!(:view, :whatsapp_campaigns) }, only: [:index, :show]
  before_action -> { check_permission!(:manage, :whatsapp_campaigns) }, except: [:index, :show]
  before_action :set_template, only: [:show, :edit, :update, :destroy, :new_campaign]

  def index
    @filters = template_filters
    @templates = apply_filters(template_scope.ordered).paginate(page: params[:page], per_page: 25)
    @approved_count = template_scope.where(status: "APPROVED").count
    @pending_count = template_scope.where(status: "PENDING").count
    @sender_number = sender_number_scope.active.find_by(id: params[:whatsapp_sender_number_id])
    @page_title = "Templates WhatsApp"
  end

  def sync
    result = Whatsapp::SyncTemplatesJob.perform_now(current_tenant.id)
    if result[:ok]
      redirect_to admin_whatsapp_templates_path, notice: "#{result[:synced]} template(s) sincronizado(s)."
    else
      redirect_to admin_whatsapp_templates_path, alert: result[:error].presence || "Não foi possível sincronizar templates."
    end
  end

  def upload_media
    upload = Whatsapp::TemplateMediaHandleUploader.upload_attachable(
      attachable: params[:file],
      media_type: params[:media_type],
      client: Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(current_tenant))
    )

    if upload[:ok]
      render json: { handle: upload[:handle] }
    else
      render json: { error: upload[:error].presence || "Não foi possível validar a mídia na Meta." },
             status: :unprocessable_entity
    end
  end

  def new
    @template_type = params[:template_type].presence
    @template = build_template
    @sender_number = selected_sender_number
    @page_title = @template_type.present? ? "Novo template WhatsApp" : "Escolha o tipo de template"
  end

  def create
    @template = template_scope.new(template_params)
    @template.status = "PENDING"
    @template.buttons = @template.clean_buttons
    @template.carousel_cards = @template.clean_carousel_cards
    @template.flow_config = @template.clean_flow_config
    result = Whatsapp::TemplateSubmission.call(template: @template)

    if result[:ok]
      redirect_to admin_whatsapp_templates_path(whatsapp_sender_number_id: selected_sender_number&.id),
                  notice: "Modelo enviado para aprovação. Acompanhe o status retornado pela Meta nesta listagem."
    else
      @template_type = @template.template_type
      @sender_number = selected_sender_number
      @template.errors.add(:base, result[:error]) if @template.errors.empty? && result[:error].present?
      flash.now[:alert] = result[:error]
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @page_title = @template.name
  end

  def edit
    @template_type = @template.template_type
    @page_title = "Editar template WhatsApp"
  end

  def update
    @template.assign_attributes(template_params)
    @template.buttons = @template.clean_buttons
    @template.carousel_cards = @template.clean_carousel_cards
    @template.flow_config = @template.clean_flow_config

    if @template.save
      redirect_to admin_whatsapp_template_path(@template), notice: "Template atualizado."
    else
      @template_type = @template.template_type
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @template.whatsapp_campaigns.exists?
      redirect_to admin_whatsapp_templates_path, alert: "Este template já está vinculado a campanhas."
      return
    end

    @template.destroy
    redirect_to admin_whatsapp_templates_path, notice: "Template removido."
  end

  def new_campaign
    unless @template.approved?
      redirect_to admin_whatsapp_templates_path, alert: "Apenas templates aprovados podem iniciar campanha."
      return
    end

    redirect_to new_admin_whatsapp_campaign_path(
      whatsapp_template_id: @template.id,
      whatsapp_sender_number_id: params[:whatsapp_sender_number_id].presence
    )
  end

  private

  def set_template
    @template = template_scope.find(params[:id])
  end

  def build_template
    template = template_scope.new(
      template_type: @template_type.presence || "text",
      category: "MARKETING",
      language: "pt_BR",
      header_format: "none",
      buttons: [],
      flow_config: {
        "button_text" => "Abrir",
        "action" => "navigate"
      }
    )
    template.carousel_cards = [
      { "media_type" => "image", "text" => "", "button_text" => "", "button_url" => "" },
      { "media_type" => "image", "text" => "", "button_text" => "", "button_url" => "" }
    ] if template.template_type == "carousel"
    template
  end

  def selected_sender_number
    sender_number_scope.active.find_by(id: params[:whatsapp_sender_number_id]) || sender_number_scope.active.order(:label, :display_phone_number).first
  end

  def template_filters
    {
      query: params[:query].to_s.strip.presence,
      status: params[:status].to_s.presence,
      category: params[:category].to_s.presence,
      template_type: params[:template_type].to_s.presence
    }.compact
  end

  def apply_filters(scope)
    filters = @filters || template_filters
    scope = scope.where("name ILIKE ?", "%#{WhatsappTemplate.sanitize_sql_like(filters[:query])}%") if filters[:query].present?
    scope = scope.where(status: filters[:status]) if filters[:status].present?
    scope = scope.where(category: filters[:category]) if filters[:category].present?
    scope = scope.where(template_type: filters[:template_type]) if filters[:template_type].present?
    scope
  end

  def template_scope
    current_tenant.whatsapp_templates
  end

  def sender_number_scope
    current_tenant.whatsapp_sender_numbers
  end

  def template_params
    params.require(:whatsapp_template).permit(
      :name,
      :language,
      :category,
      :body,
      :template_type,
      :allow_category_change,
      :header_format,
      :header_text,
      :header_media_handle,
      :header_media_file,
      :footer_text,
      example_values: [],
      carousel_card_media_files: [],
      buttons: {},
      carousel_cards: {},
      flow_config: {}
    )
  end
end
