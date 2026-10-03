class Admin::HomeSettingsController < Admin::BaseController
  requires_permission :manage, :site_publico
  before_action :set_home_setting
  
  def edit
    load_home_sections
  end
  
  def update
    uploaded_hero_slide_images = Array(params.dig(:home_setting, :hero_slide_images)).reject(&:blank?)

    HomeSetting.transaction do
      @home_setting.update!(home_setting_params)
      append_hero_slides(uploaded_hero_slide_images)
    end
    redirect_to edit_admin_home_setting_path, notice: 'Configurações atualizadas com sucesso!'
  rescue ActiveRecord::RecordInvalid => error
    @home_setting.errors.add(:base, error.record.errors.full_messages.to_sentence) unless error.record == @home_setting
    @home_setting.hero_slides.reset
    load_home_sections
    render :edit, status: :unprocessable_entity
  end
  
  private

  # A aba Seções usa a mesma listagem de /admin/home_sections (a tela também renderiza ao falhar a validação).
  def load_home_sections
    @home_sections = current_tenant.home_sections.ordered.includes(:home_section_items)
  end

  def set_home_setting
    @home_setting = HomeSetting.instance(tenant: current_tenant)
  end
  
  def home_setting_params
    permitted_params = params.require(:home_setting).permit(
      :hero_title,
      :hero_subtitle,
      :hero_title_font_size,
      :hero_subtitle_font_size,
      :hero_cta_text,
      :hero_layout,
      :hero_search_align,
      :hero_ai_search_enabled,
      :hero_ai_suggestions,
      :overlay_opacity,
      :overlay_color,
      :hero_background_desktop,
      :hero_background_mobile,
      :hero_button_color,
      :hero_button_text_color,
      :search_filter_background_color,
      :search_filter_background_opacity,
      :search_filter_border_enabled,
      :search_filter_border_color,
      :search_filter_border_opacity,
      :search_filter_text_color,
      :search_filter_field_background_color,
      :search_filter_field_background_opacity,
      :search_filter_backdrop_blur,
      :search_filter_border_radius,
      :search_filter_display_mode,
      :mobile_search_filter_display_mode,
      hero_slide_images: [],
      hero_slides_attributes: [:id, :position, :active, :alt_text, :_destroy]
    )

    permitted_params.except(:hero_slide_images)
  end

  def append_hero_slides(files)
    return if files.blank?

    next_position = @home_setting.hero_slides.maximum(:position).to_i

    files.each do |file|
      next_position += 1
      slide = @home_setting.hero_slides.build(
        position: next_position,
        active: true,
        alt_text: "#{current_tenant.name} - Imagem #{next_position}"
      )
      slide.image.attach(file)
      slide.save!
    end
  end
end
