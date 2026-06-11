class Admin::HomeSettingsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_home_setting
  
  def edit
    # @home_setting já está definido
  end
  
  def update
    uploaded_hero_slide_images = Array(params.dig(:home_setting, :hero_slide_images)).reject(&:blank?)

    if @home_setting.update(home_setting_params)
      append_hero_slides(uploaded_hero_slide_images)
      redirect_to edit_admin_home_setting_path, notice: 'Configurações atualizadas com sucesso!'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_home_setting
    @home_setting = HomeSetting.instance
  end
  
  def home_setting_params
    permitted_params = params.require(:home_setting).permit(
      :hero_title,
      :hero_subtitle,
      :hero_title_font_size,
      :hero_subtitle_font_size,
      :hero_cta_text,
      :hero_cta_link,
      :overlay_opacity,
      :overlay_color,
      :cta_title,
      :cta_subtitle,
      :services_active,
      :why_choose_active,
      :cta_contact_active,
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
      optimized_file = HomeHeroSlide.optimized_upload_file(file)
      slide = @home_setting.hero_slides.build(
        position: next_position,
        active: true,
        alt_text: "Salute Imóveis - Imagem #{next_position}"
      )
      slide.image.attach(
        io: optimized_file,
        filename: HomeHeroSlide.optimized_filename(file),
        content_type: "image/jpeg"
      )
      slide.save!
      slide.image.blob.update!(metadata: slide.image.blob.metadata.merge("optimized_for_web" => true))
    rescue StandardError => e
      Rails.logger.error("[HomeHeroSlide] Falha ao otimizar imagem do hero: #{e.class} - #{e.message}")
    ensure
      optimized_file&.close
      optimized_file&.unlink
    end
  end
end
